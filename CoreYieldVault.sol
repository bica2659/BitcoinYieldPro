// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CoreYieldVault
 * @dev A smart contract for Bitcoin yield farming on Core blockchain
 * @notice This contract leverages Core's Bitcoin-native DeFi capabilities
 * @notice Built specifically for the Core blockchain hackathon
 */
contract CoreYieldVault is ReentrancyGuard, Pausable, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Events
    event Deposit(address indexed user, uint256 amount, uint256 shares, uint256 timestamp);
    event Withdrawal(address indexed user, uint256 amount, uint256 shares, uint256 timestamp);
    event YieldHarvested(uint256 totalYield, uint256 coreRewards, uint256 timestamp);
    event CoreStakingReward(address indexed user, uint256 amount, uint256 timestamp);
    event LiquidityProvided(address indexed user, uint256 btcAmount, uint256 coreAmount);
    event DelegatedStaking(address indexed validator, uint256 amount, uint256 timestamp);
    event FeesCollected(uint256 managementFee, uint256 performanceFee);

    // Core blockchain specific interfaces
interface ICoreStaking {
    function delegate(address validator, uint256 amount) external;
    function undelegate(address validator, uint256 amount) external;
    function claimRewards() external returns (uint256);
    function getRewards(address delegator) external view returns (uint256);
}

interface ICoreBridge {
    function depositBTC(uint256 amount) external payable;
    function withdrawBTC(uint256 amount) external;
    function getBTCBalance(address user) external view returns (uint256);
}

    // State variables
    IERC20 public immutable coreBTC; // Wrapped Bitcoin on Core
    IERC20 public immutable coreToken; // Native CORE token
    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalShares;
    uint256 public totalAssets;
    uint256 public totalCoreRewards;
    uint256 public totalBTCRewards;
    
    // Core blockchain specific
    ICoreStaking public coreStaking;
    ICoreBridge public coreBridge;
    address public validatorAddress;
    uint256 public stakingRatio = 5000; // 50% of funds go to Core staking
    uint256 public liquidityRatio = 3000; // 30% for liquidity provision
    uint256 public reserveRatio = 2000; // 20% kept as reserve
    
    // Fee structure (basis points)
    uint256 public managementFee = 150; // 1.5% annual
    uint256 public performanceFee = 800; // 8% of profits
    uint256 public coreDelegationFee = 50; // 0.5% for Core delegation rewards
    uint256 public constant MAX_FEE = 3000; // 30% max fee
    uint256 public constant FEE_DENOMINATOR = 10000;

    // User balances and staking info
    mapping(address => uint256) public shares;
    mapping(address => uint256) public lastDepositTime;
    mapping(address => uint256) public coreRewardsClaimed;
    mapping(address => bool) public isValidator;
    
    // Yield strategies
    address public yieldStrategy;
    address public liquidityPool;
    uint256 public lastHarvestTime;
    uint256 public totalYieldEarned;
    
    // Core blockchain specific features
    uint256 public minCoreStaking = 1 ether; // Minimum CORE for staking
    uint256 public lockPeriod = 7 days; // 7-day lock period for Core staking
    bool public autoCompounding = true;

    struct UserInfo {
        uint256 shares;
        uint256 lastDepositTime;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 coreStaked;
        uint256 btcProvided;
        uint256 rewardsEarned;
    }

    struct StrategyInfo {
        uint256 totalBTCInStrategy;
        uint256 totalCoreInStrategy;
        uint256 totalRewardsGenerated;
        uint256 avgAPY;
        bool isActive;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(address => StrategyInfo) public strategyInfo;

    // Core blockchain validator info
    struct ValidatorInfo {
        address validatorAddress;
        uint256 totalDelegated;
        uint256 commission;
        uint256 rewards;
        bool isActive;
    }

    mapping(address => ValidatorInfo) public validators;
    address[] public activeValidators;

    /**
     * @dev Constructor
     * @param _coreBTC Wrapped Bitcoin token address on Core
     * @param _coreToken Native CORE token address
     * @param _coreStaking Core staking contract address
     * @param _coreBridge Core bridge contract address
     * @param _validatorAddress Default validator for delegation
     */
    constructor(
        IERC20 _coreBTC,
        IERC20 _coreToken,
        ICoreStaking _coreStaking,
        ICoreBridge _coreBridge,
        address _validatorAddress,
        string memory _name,
        string memory _symbol
    ) {
        coreBTC = _coreBTC;
        coreToken = _coreToken;
        coreStaking = _coreStaking;
        coreBridge = _coreBridge;
        validatorAddress = _validatorAddress;
        name = _name;
        symbol = _symbol;
        decimals = 18;
        lastHarvestTime = block.timestamp;

        // Initialize default validator
        validators[_validatorAddress] = ValidatorInfo({
            validatorAddress: _validatorAddress,
            totalDelegated: 0,
            commission: 500, // 5%
            rewards: 0,
            isActive: true
        });
        activeValidators.push(_validatorAddress);
    }

    /**
     * @dev Deposit BTC and CORE tokens for yield farming
     * @param btcAmount Amount of BTC to deposit
     * @param coreAmount Amount of CORE to deposit (optional)
     */
    function deposit(uint256 btcAmount, uint256 coreAmount) external payable nonReentrant whenNotPaused {
        require(btcAmount > 0 || coreAmount > 0, "Must deposit something");
        require(btcAmount <= msg.value, "Insufficient BTC sent");

        uint256 totalValue = btcAmount;
        if (coreAmount > 0) {
            totalValue = totalValue.add(coreAmount);
        }

        // Calculate shares to mint
        uint256 sharesToMint = totalShares == 0 
            ? totalValue 
            : totalValue.mul(totalShares).div(totalAssets);

        // Update state
        shares[msg.sender] = shares[msg.sender].add(sharesToMint);
        totalShares = totalShares.add(sharesToMint);
        totalAssets = totalAssets.add(totalValue);
        
        // Update user info
        UserInfo storage user = userInfo[msg.sender];
        user.shares = user.shares.add(sharesToMint);
        user.lastDepositTime = block.timestamp;
        user.totalDeposited = user.totalDeposited.add(totalValue);

        // Handle BTC deposit
        if (btcAmount > 0) {
            coreBridge.depositBTC{value: btcAmount}(btcAmount);
            user.btcProvided = user.btcProvided.add(btcAmount);
        }

        // Handle CORE deposit
        if (coreAmount > 0) {
            coreToken.safeTransferFrom(msg.sender, address(this), coreAmount);
            user.coreStaked = user.coreStaked.add(coreAmount);
        }

        // Auto-deploy to strategies
        _deployToStrategies(btcAmount, coreAmount);

        emit Deposit(msg.sender, totalValue, sharesToMint, block.timestamp);
    }

    /**
     * @dev Withdraw assets from the vault
     * @param sharesToRedeem Number of shares to redeem
     */
    function withdraw(uint256 sharesToRedeem) external nonReentrant {
        require(sharesToRedeem > 0, "Cannot withdraw zero shares");
        require(shares[msg.sender] >= sharesToRedeem, "Insufficient shares");
        
        UserInfo storage user = userInfo[msg.sender];
        
        // Check lock period for Core staking
        require(
            block.timestamp >= user.lastDepositTime.add(lockPeriod),
            "Funds are still locked"
        );

        // Calculate assets to withdraw
        uint256 assetsToWithdraw = sharesToRedeem.mul(totalAssets).div(totalShares);
        uint256 btcToWithdraw = sharesToRedeem.mul(user.btcProvided).div(user.shares);
        uint256 coreToWithdraw = sharesToRedeem.mul(user.coreStaked).div(user.shares);

        // Update state
        shares[msg.sender] = shares[msg.sender].sub(sharesToRedeem);
        totalShares = totalShares.sub(sharesToRedeem);
        totalAssets = totalAssets.sub(assetsToWithdraw);
        
        // Update user info
        user.shares = user.shares.sub(sharesToRedeem);
        user.totalWithdrawn = user.totalWithdrawn.add(assetsToWithdraw);
        user.btcProvided = user.btcProvided.sub(btcToWithdraw);
        user.coreStaked = user.coreStaked.sub(coreToWithdraw);

        // Withdraw from strategies
        _withdrawFromStrategies(btcToWithdraw, coreToWithdraw);

        // Transfer BTC
        if (btcToWithdraw > 0) {
            coreBridge.withdrawBTC(btcToWithdraw);
            payable(msg.sender).transfer(btcToWithdraw);
        }

        // Transfer CORE
        if (coreToWithdraw > 0) {
            coreToken.safeTransfer(msg.sender, coreToWithdraw);
        }

        emit Withdrawal(msg.sender, assetsToWithdraw, sharesToRedeem, block.timestamp);
    }

    /**
     * @dev Harvest yield from all strategies
     */
    function harvestYield() external onlyOwner {
        require(
            block.timestamp >= lastHarvestTime.add(1 hours),
            "Too early to harvest"
        );

        uint256 totalYield = 0;
        uint256 coreRewards = 0;

        // Harvest from Core staking
        coreRewards = coreStaking.claimRewards();
        if (coreRewards > 0) {
            totalCoreRewards = totalCoreRewards.add(coreRewards);
            totalYield = totalYield.add(coreRewards);
        }

        // Harvest from liquidity pools
        if (liquidityPool != address(0)) {
            (bool success, bytes memory data) = liquidityPool.call(
                abi.encodeWithSignature("harvestRewards()")
            );
            if (success && data.length > 0) {
                uint256 lpRewards = abi.decode(data, (uint256));
                totalYield = totalYield.add(lpRewards);
            }
        }

        if (totalYield > 0) {
            // Calculate fees
            uint256 perfFee = totalYield.mul(performanceFee).div(FEE_DENOMINATOR);
            uint256 mgmtFee = totalAssets.mul(managementFee)
                .mul(block.timestamp.sub(lastHarvestTime))
                .div(365 days)
                .div(FEE_DENOMINATOR);
            
            uint256 totalFees = perfFee.add(mgmtFee);
            uint256 netYield = totalYield.sub(totalFees);

            // Update total assets with net yield
            totalAssets = totalAssets.add(netYield);
            totalYieldEarned = totalYieldEarned.add(totalYield);

            // Auto-compound if enabled
            if (autoCompounding) {
                _reinvestYield(netYield);
            }

            // Transfer fees to owner
            if (totalFees > 0) {
                coreToken.safeTransfer(owner(), totalFees);
            }

            emit YieldHarvested(totalYield, coreRewards, block.timestamp);
            emit FeesCollected(mgmtFee, perfFee);
        }

        lastHarvestTime = block.timestamp;
    }

    /**
     * @dev Delegate CORE tokens to a validator
     * @param validator Address of the validator
     * @param amount Amount of CORE to delegate
     */
    function delegateToValidator(address validator, uint256 amount) external onlyOwner {
        require(validators[validator].isActive, "Validator not active");
        require(coreToken.balanceOf(address(this)) >= amount, "Insufficient CORE balance");

        // Approve and delegate
        coreToken.safeApprove(address(coreStaking), amount);
        coreStaking.delegate(validator, amount);

        // Update validator info
        validators[validator].totalDelegated = validators[validator].totalDelegated.add(amount);

        emit DelegatedStaking(validator, amount, block.timestamp);
    }

    /**
     * @dev Deploy funds to various yield strategies
     * @param btcAmount Amount of BTC to deploy
     * @param coreAmount Amount of CORE to deploy
     */
    function _deployToStrategies(uint256 btcAmount, uint256 coreAmount) internal {
        // Deploy to Core staking (50% of CORE)
        if (coreAmount > 0) {
            uint256 stakingAmount = coreAmount.mul(stakingRatio).div(FEE_DENOMINATOR);
            if (stakingAmount >= minCoreStaking) {
                coreToken.safeApprove(address(coreStaking), stakingAmount);
                coreStaking.delegate(validatorAddress, stakingAmount);
                validators[validatorAddress].totalDelegated = validators[validatorAddress].totalDelegated.add(stakingAmount);
            }
        }

        // Deploy to liquidity pools (30% of total)
        if (liquidityPool != address(0) && (btcAmount > 0 || coreAmount > 0)) {
            uint256 lpBTCAmount = btcAmount.mul(liquidityRatio).div(FEE_DENOMINATOR);
            uint256 lpCoreAmount = coreAmount.mul(liquidityRatio).div(FEE_DENOMINATOR);
            
            if (lpBTCAmount > 0 || lpCoreAmount > 0) {
                _provideLiquidity(lpBTCAmount, lpCoreAmount);
            }
        }
    }

    /**
     * @dev Withdraw funds from strategies
     * @param btcAmount Amount of BTC to withdraw
     * @param coreAmount Amount of CORE to withdraw
     */
    function _withdrawFromStrategies(uint256 btcAmount, uint256 coreAmount) internal {
        // Withdraw from Core staking
        if (coreAmount > 0) {
            uint256 stakedAmount = coreAmount.mul(stakingRatio).div(FEE_DENOMINATOR);
            if (stakedAmount > 0) {
                coreStaking.undelegate(validatorAddress, stakedAmount);
                validators[validatorAddress].totalDelegated = validators[validatorAddress].totalDelegated.sub(stakedAmount);
            }
        }

        // Withdraw from liquidity pools
        if (liquidityPool != address(0)) {
            (bool success, ) = liquidityPool.call(
                abi.encodeWithSignature("removeLiquidity(uint256,uint256)", btcAmount, coreAmount)
            );
            require(success, "Liquidity withdrawal failed");
        }
    }

    /**
     * @dev Provide liquidity to Core DEX
     * @param btcAmount Amount of BTC
     * @param coreAmount Amount of CORE
     */
    function _provideLiquidity(uint256 btcAmount, uint256 coreAmount) internal {
        if (liquidityPool != address(0)) {
            // Approve tokens
            if (btcAmount > 0) {
                coreBTC.safeApprove(liquidityPool, btcAmount);
            }
            if (coreAmount > 0) {
                coreToken.safeApprove(liquidityPool, coreAmount);
            }

            // Provide liquidity
            (bool success, ) = liquidityPool.call{value: btcAmount}(
                abi.encodeWithSignature("addLiquidity(uint256,uint256)", btcAmount, coreAmount)
            );
            require(success, "Liquidity provision failed");

            emit LiquidityProvided(msg.sender, btcAmount, coreAmount);
        }
    }

    /**
     * @dev Reinvest harvested yield
     * @param yieldAmount Amount of yield to reinvest
     */
    function _reinvestYield(uint256 yieldAmount) internal {
        if (yieldAmount > 0) {
            // Reinvest in the same strategies
            uint256 coreToStake = yieldAmount.mul(stakingRatio).div(FEE_DENOMINATOR);
            uint256 coreToLP = yieldAmount.mul(liquidityRatio).div(FEE_DENOMINATOR);
            
            // Stake more CORE
            if (coreToStake > 0) {
                coreToken.safeApprove(address(coreStaking), coreToStake);
                coreStaking.delegate(validatorAddress, coreToStake);
            }
            
            // Provide more liquidity
            if (coreToLP > 0 && liquidityPool != address(0)) {
                coreToken.safeApprove(liquidityPool, coreToLP);
                (bool success, ) = liquidityPool.call(
                    abi.encodeWithSignature("addLiquidity(uint256,uint256)", 0, coreToLP)
                );
                require(success, "Yield reinvestment failed");
            }
        }
    }

    // View functions

    /**
     * @dev Get current share price
     */
    function sharePrice() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return totalAssets.mul(1e18).div(totalShares);
    }

    /**
     * @dev Get user's asset balance
     */
    function balanceOf(address user) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return shares[user].mul(totalAssets).div(totalShares);
    }

    /**
     * @dev Get Core staking rewards for the vault
     */
    function getCoreStakingRewards() external view returns (uint256) {
        return coreStaking.getRewards(address(this));
    }

    /**
     * @dev Get comprehensive vault information
     */
    function getVaultInfo() external view returns (
        uint256 _totalAssets,
        uint256 _totalShares,
        uint256 _sharePrice,
        uint256 _totalYieldEarned,
        uint256 _totalCoreRewards,
        uint256 _totalBTCRewards,
        uint256 _lastHarvestTime,
        bool _autoCompounding
    ) {
        _totalAssets = totalAssets;
        _totalShares = totalShares;
        _sharePrice = totalShares == 0 ? 1e18 : totalAssets.mul(1e18).div(totalShares);
        _totalYieldEarned = totalYieldEarned;
        _totalCoreRewards = totalCoreRewards;
        _totalBTCRewards = totalBTCRewards;
        _lastHarvestTime = lastHarvestTime;
        _autoCompounding = autoCompounding;
    }

    // Admin functions

    /**
     * @dev Set liquidity pool address
     */
    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        liquidityPool = _liquidityPool;
    }

    /**
     * @dev Add a new validator
     */
    function addValidator(address _validator, uint256 _commission) external onlyOwner {
        require(!validators[_validator].isActive, "Validator already exists");
        
        validators[_validator] = ValidatorInfo({
            validatorAddress: _validator,
            totalDelegated: 0,
            commission: _commission,
            rewards: 0,
            isActive: true
        });
        activeValidators.push(_validator);
    }

    /**
     * @dev Toggle auto-compounding
     */
    function setAutoCompounding(bool _enabled) external onlyOwner {
        autoCompounding = _enabled;
    }

    /**
     * @dev Update strategy ratios
     */
    function updateStrategyRatios(
        uint256 _stakingRatio,
        uint256 _liquidityRatio,
        uint256 _reserveRatio
    ) external onlyOwner {
        require(_stakingRatio.add(_liquidityRatio).add(_reserveRatio) == FEE_DENOMINATOR, "Ratios must sum to 100%");
        
        stakingRatio = _stakingRatio;
        liquidityRatio = _liquidityRatio;
        reserveRatio = _reserveRatio;
    }

    /**
     * @dev Emergency functions
     */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Receive BTC payments
     */
    receive() external payable {
        // Allow receiving BTC for bridge operations
    }
}

	

