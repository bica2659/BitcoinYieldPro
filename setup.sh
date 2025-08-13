#!/bin/bash

# BitcoinYield-Pro Setup Script
# This script sets up the development environment

set -e

echo "🚀 Setting up BitcoinYield-Pro development environment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on supported OS
check_os() {
    print_status "Checking operating system..."
    OS=$(uname -s)
    case $OS in
        Linux*)     MACHINE=Linux;;
        Darwin*)    MACHINE=Mac;;
        CYGWIN*)    MACHINE=Cygwin;;
        MINGW*)     MACHINE=MinGw;;
        *)          MACHINE="UNKNOWN:${unameOut}"
    esac
    print_success "Detected OS: $MACHINE"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js 18+ from https://nodejs.org/"
        exit 1
    fi
    
    NODE_VERSION=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
    if [ $NODE_VERSION -lt 18 ]; then
        print_error "Node.js version 18+ is required. Current version: $(node -v)"
        exit 1
    fi
    print_success "Node.js $(node -v) ✓"
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed"
        exit 1
    fi
    print_success "npm $(npm -v) ✓"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed. Some features will not be available."
        print_warning "Install Docker from https://docs.docker.com/get-docker/"
    else
        print_success "Docker $(docker --version | cut -d ' ' -f 3 | cut -d ',' -f 1) ✓"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        if ! docker compose version &> /dev/null; then
            print_warning "Docker Compose is not available"
        else
            print_success "Docker Compose (plugin) ✓"
        fi
    else
        print_success "Docker Compose $(docker-compose --version | cut -d ' ' -f 3 | cut -d ',' -f 1) ✓"
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed"
        exit 1
    fi
    print_success "Git $(git --version | cut -d ' ' -f 3) ✓"
}

# Create directory structure
create_directories() {
    print_status "Creating project structure..."
    
    directories=(
        "frontend/src/components"
        "frontend/src/pages"
        "frontend/src/utils"
        "frontend/src/hooks"
        "frontend/src/services"
        "frontend/src/styles"
        "frontend/public"
        "backend/src/controllers"
        "backend/src/models"
        "backend/src/services"
        "backend/src/routes"
        "backend/src/middleware"
        "backend/src/utils"
        "smart-contracts/rootstock/contracts"
        "smart-contracts/rootstock/scripts"
        "smart-contracts/rootstock/test"
        "smart-contracts/stacks/contracts"
        "smart-contracts/stacks/tests"
        "smart-contracts/bitcoin-scripts"
        "blockchain/bitcoin"
        "blockchain/lightning"
        "blockchain/indexer"
        "docs"
        "tests/unit"
        "tests/integration"
        "tests/e2e"
        "scripts"
        "config"
        "monitoring"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done
    
    print_success "Directory structure created"
}

# Create environment files
create_env_files() {
    print_status "Creating environment configuration files..."
    
    # Root .env file
    if [ ! -f ".env" ]; then
        cat > .env << EOL
# BitcoinYield-Pro Environment Configuration

# Application
NODE_ENV=development
PORT=3001

# Bitcoin Network (regtest for development)
BITCOIN_NETWORK=regtest
BITCOIN_RPC_URL=http://bitcoin:password123@localhost:18443
BITCOIN_RPC_USER=bitcoin
BITCOIN_RPC_PASSWORD=password123

# Lightning Network
LND_HOST=localhost:10009
LND_CERT_PATH=./blockchain/lightning/tls.cert
LND_MACAROON_PATH=./blockchain/lightning/admin.macaroon

# Rootstock (RSK)
RSK_NETWORK=regtest
RSK_RPC_URL=http://localhost:4444

# Stacks
STACKS_NETWORK=testnet
STACKS_API_URL=https://stacks-node-api.testnet.stacks.co

# Database
MONGODB_URI=mongodb://admin:password123@localhost:27017/bitcoinyield?authSource=admin
REDIS_URL=redis://localhost:6379

# Security
JWT_SECRET=your-super-secret-jwt-key-change-in-production-$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)

# API Keys (add your own)
COINDESK_API_KEY=
BLOCKCHAIN_INFO_API_KEY=
MEMPOOL_SPACE_API_KEY=

# Monitoring
PROMETHEUS_PORT=9090
GRAFANA_PORT=3002

# Features
ENABLE_YIELD_FARMING=true
ENABLE_LIGHTNING=true
ENABLE_SMART_CONTRACTS=true
ENABLE_MONITORING=false
EOL
        print_success "Created .env file"
    else
        print_warning ".env file already exists, skipping"
    fi
    
    # Frontend .env
    if [ ! -f "frontend/.env" ]; then
        cat > frontend/.env << EOL
VITE_API_URL=http://localhost:3001
VITE_WS_URL=ws://localhost:3001
VITE_NETWORK=regtest
VITE_ENABLE_DEVTOOLS=true
EOL
        print_success "Created frontend/.env file"
    fi
    
    # Backend .env
    if [ ! -f "backend/.env" ]; then
        ln -sf ../.env backend/.env
        print_success "Linked backend/.env file"
    fi
}

# Initialize frontend
setup_frontend() {
    print_status "Setting up frontend..."
    
    cd frontend
    
    if [ ! -f "package.json" ]; then
        cat > package.json << EOL
{
  "name": "bitcoin-yield-pro-frontend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "test": "vitest",
    "lint": "eslint src --ext .js,.jsx,.ts,.tsx",
    "lint:fix": "eslint src --ext .js,.jsx,.ts,.tsx --fix"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.8.0",
    "axios": "^1.6.0",
    "web3": "^4.0.0",
    "@web3modal/ethereum": "^2.7.0",
    "wagmi": "^1.4.0",
    "chart.js": "^4.4.0",
    "react-chartjs-2": "^5.2.0",
    "tailwindcss": "^3.3.0",
    "lucide-react": "^0.263.1",
    "react-query": "^3.39.0",
    "zustand": "^4.4.0",
    "react-hook-form": "^7.47.0",
    "react-hot-toast": "^2.4.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "@vitejs/plugin-react": "^4.0.0",
    "vite": "^4.4.0",
    "vitest": "^0.34.0",
    "eslint": "^8.45.0",
    "eslint-plugin-react": "^7.32.0",
    "eslint-plugin-react-hooks": "^4.6.0",
    "autoprefixer": "^10.4.14",
    "postcss": "^8.4.24",
    "@tailwindcss/forms": "^0.5.4"
  }
}
EOL
        print_success "Created frontend package.json"
    fi
    
    cd ..
}

# Initialize backend
setup_backend() {
    print_status "Setting up backend..."
    
    cd backend
    
    if [ ! -f "package.json" ]; then
        cat > package.json << EOL
{
  "name": "bitcoin-yield-pro-backend",
  "version": "1.0.0",
  "main": "server.js",
  "type": "module",
  "scripts": {
    "dev": "nodemon server.js",
    "start": "node server.js",
    "test": "jest",
    "test:watch": "jest --watch",
    "lint": "eslint src --ext .js",
    "lint:fix": "eslint src --ext .js --fix"
  },
  "dependencies": {
    "express": "^4.18.0",
    "mongoose": "^7.5.0",
    "redis": "^4.6.0",
    "jsonwebtoken": "^9.0.0",
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "express-rate-limit": "^6.10.0",
    "dotenv": "^16.3.0",
    "axios": "^1.5.0",
    "ws": "^8.14.0",
    "bitcoinjs-lib": "^6.1.0",
    "@lightning-labs/lnd-grpc": "^0.3.0",
    "web3": "^4.0.0",
    "socket.io": "^4.7.0",
    "joi": "^17.9.0",
    "winston": "^3.10.0",
    "express-validator": "^7.0.0",
    "multer": "^1.4.5"
  },
  "devDependencies": {
    "nodemon": "^3.0.0",
    "jest": "^29.7.0",
    "supertest": "^6.3.0",
    "eslint": "^8.45.0"
  }
}
EOL
        print_success "Created backend package.json"
    fi
    
    cd ..
}

# Initialize smart contracts
setup_smart_contracts() {
    print_status "Setting up smart contracts..."
    
    # Rootstock setup
    cd smart-contracts/rootstock
    if [ ! -f "package.json" ]; then
        cat > package.json << EOL
{
  "name": "bitcoin-yield-pro-contracts",
  "version": "1.0.0",
  "scripts": {
    "compile": "hardhat compile",
    "test": "hardhat test",
    "deploy:regtest": "hardhat run scripts/deploy.js --network regtest",
    "deploy:testnet": "hardhat run scripts/deploy.js --network testnet",
    "verify": "hardhat verify --network testnet"
  },
  "dependencies": {
    "@openzeppelin/contracts": "^4.9.0"
  },
  "devDependencies": {
    "@nomiclabs/hardhat-ethers": "^2.2.0",
    "@nomiclabs/hardhat-waffle": "^2.0.0",
    "hardhat": "^2.17.0",
    "ethers": "^5.7.0",
    "chai": "^4.3.0"
  }
}
EOL
        print_success "Created smart contracts package.json"
    fi
    
    # Create hardhat config
    if [ ! -f "hardhat.config.js" ]; then
        cat > hardhat.config.js << 'EOL'
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001";

module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    regtest: {
      url: "http://localhost:4444",
      accounts: [PRIVATE_KEY],
      chainId: 33
    },
    testnet: {
      url: "https://public-node.testnet.rsk.co",
      accounts: [PRIVATE_KEY],
      chainId: 31
    },
    mainnet: {
      url: "https://public-node.rsk.co",
      accounts: [PRIVATE_KEY],
      chainId: 30
    }
  }
};
EOL
        print_success "Created hardhat.config.js"
    fi
    
    cd ../../..
    
    # Stacks setup
    cd smart-contracts/stacks
    if [ ! -f "Clarinet.toml" ]; then
        cat > Clarinet.toml << EOL
[project]
name = "bitcoin-yield-pro-stacks"
description = "Bitcoin Yield Pro smart contracts for Stacks"
authors = ["Your Name <your.email@example.com>"]
telemetry = false
cache_dir = ".clarinet"

[contracts.yield-vault]
path = "contracts/yield-vault.clar"
depends_on = []

[repl.analysis]
passes = ["check_checker"]

[repl.analysis.check_checker]
strict = false
trusted_sender = false
trusted_caller = false
callee_filter = false
EOL
        print_success "Created Clarinet.toml"
    fi
    
    cd ../..
}

# Install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    
    # Install root dependencies
    if [ -f "package.json" ]; then
        npm install
        print_success "Root dependencies installed"
    fi
    
    # Install frontend dependencies
    if [ -f "frontend/package.json" ]; then
        cd frontend
        npm install
        cd ..
        print_success "Frontend dependencies installed"
    fi
    
    # Install backend dependencies
    if [ -f "backend/package.json" ]; then
        cd backend
        npm install
        cd ..
        print_success "Backend dependencies installed"
    fi
    
    # Install smart contract dependencies
    if [ -f "smart-contracts/core/package.json" ]; then
        cd smart-contracts/core
        npm install
        cd ../..
        print_success "Core blockchain contract dependencies installed"
    fi
    
    if [ -f "smart-contracts/rootstock/package.json" ]; then
        cd smart-contracts/rootstock
        npm install
        cd ../..
        print_success "Rootstock contract dependencies installed"
    fi
}

# Create initial files
create_initial_files() {
    print_status "Creating initial project files..."
    
    # Create frontend index.html
    if [ ! -f "frontend/index.html" ]; then
        cat > frontend/index.html << 'EOL'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/bitcoin-logo.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>BitcoinYield Pro - Professional Bitcoin DeFi Platform</title>
    <meta name="description" content="Professional Bitcoin yield farming and DeFi platform" />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOL
    fi
    
    # Create backend server.js
    if [ ! -f "backend/server.js" ]; then
        cat > backend/server.js << 'EOL'
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// API routes
app.get('/api/v1', (req, res) => {
  res.json({
    message: 'BitcoinYield Pro API v1.0',
    status: 'Active',
    endpoints: {
      auth: '/api/v1/auth',
      portfolio: '/api/v1/portfolio',
      yield: '/api/v1/yield',
      analytics: '/api/v1/analytics'
    }
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Endpoint not found',
    path: req.originalUrl
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Something went wrong'
  });
});

app.listen(PORT, () => {
  console.log(`🚀 BitcoinYield Pro API server running on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`🔗 API endpoint: http://localhost:${PORT}/api/v1`);
});
EOL
    fi
}

# Main setup function
main() {
    echo "🏗️  BitcoinYield-Pro Development Environment Setup"
    echo "================================================"
    
    check_os
    check_prerequisites
    create_directories
    create_env_files
    setup_frontend
    setup_backend
    setup_smart_contracts
    create_initial_files
    install_dependencies
    
    print_success "✅ Setup completed successfully!"
    echo ""
    echo "🎉 BitcoinYield-Pro is ready for development!"
    echo ""
    echo "Next steps:"
    echo "1. Review and update the .env file with your configuration"
    echo "2. Start the development environment:"
    echo "   npm run dev              # Start both frontend and backend"
    echo "   npm run docker:dev       # Start with Docker (includes Bitcoin, Lightning, etc.)"
    echo ""
    echo "3. Access the application:"
    echo "   Frontend:  http://localhost:3000"
    echo "   Backend:   http://localhost:3001"
    echo "   Health:    http://localhost:3001/health"
    echo ""
    echo "4. For Docker services:"
    echo "   Bitcoin:   localhost:18443 (regtest)"
    echo "   Lightning: localhost:10009 (gRPC), localhost:8080 (REST)"
    echo "   Core:      localhost:8545 (RPC), localhost:8546 (WebSocket)"
    echo "   RSK:       localhost:4444 (RPC), localhost:5050 (WebSocket)"
    echo "   MongoDB:   localhost:27017"
    echo "   Redis:     localhost:6379"
    echo ""
    echo "📚 Check the README.md file for detailed documentation."
    echo "🤝 Happy coding!"
}

# Run main function
main "$@"
	
