#!/bin/bash
# Homebrew 和 Docker Desktop 自动安装脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo ""
echo "========================================"
echo "  Homebrew & Docker Desktop 安装脚本"
echo "========================================"
echo ""

# 检查是否已安装 Homebrew
if command -v brew &> /dev/null; then
    echo_success "Homebrew 已安装"
    brew --version
else
    echo_info "开始安装 Homebrew..."
    echo_warning "需要输入管理员密码（sudo）"
    
    # 安装 Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # 检测芯片类型并添加到 PATH
    if [[ $(uname -m) == 'arm64' ]]; then
        # Apple Silicon (M1/M2/M3)
        echo_info "检测到 Apple Silicon 芯片，配置环境变量..."
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        # Intel
        echo_info "检测到 Intel 芯片，配置环境变量..."
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    echo_success "Homebrew 安装完成！"
fi

echo ""
echo "========================================"

# 检查是否已安装 Docker
if command -v docker &> /dev/null; then
    echo_success "Docker 已安装"
    docker --version
    
    # 检查 Docker 是否在运行
    if docker info &> /dev/null; then
        echo_success "Docker 正在运行"
    else
        echo_warning "Docker 未运行，正在启动..."
        open -a Docker
        echo_info "等待 Docker 启动（约 10-20 秒）..."
        sleep 10
    fi
else
    echo_info "开始安装 Docker Desktop..."
    
    # 使用 Homebrew 安装 Docker Desktop
    brew install --cask docker
    
    echo_success "Docker Desktop 安装完成！"
    
    # 启动 Docker Desktop
    echo_info "正在启动 Docker Desktop..."
    open -a Docker
    
    echo_warning "首次启动需要 10-30 秒初始化..."
    echo_info "等待 Docker daemon 启动..."
    
    # 等待 Docker 启动（最多等待 60 秒）
    for i in {1..60}; do
        if docker info &> /dev/null 2>&1; then
            echo_success "Docker 已成功启动！"
            break
        fi
        echo -n "."
        sleep 1
    done
    echo ""
fi

echo ""
echo "========================================"
echo_info "验证安装..."
echo ""

# 验证 Homebrew
if command -v brew &> /dev/null; then
    echo_success "Homebrew: $(brew --version | head -n 1)"
else
    echo_error "Homebrew 安装失败"
    exit 1
fi

# 验证 Docker
if command -v docker &> /dev/null; then
    echo_success "Docker: $(docker --version)"
else
    echo_error "Docker 安装失败"
    exit 1
fi

# 验证 docker-compose
if command -v docker-compose &> /dev/null; then
    echo_success "Docker Compose: $(docker-compose --version)"
else
    echo_warning "docker-compose 未找到（Docker Desktop 应该包含）"
fi

# 检查 Docker 是否运行
if docker info &> /dev/null 2>&1; then
    echo_success "Docker daemon 正在运行"
else
    echo_warning "Docker daemon 未运行"
    echo_info "请手动启动 Docker Desktop: open -a Docker"
fi

echo ""
echo "========================================"
echo_success "安装完成！"
echo ""
echo "🎉 下一步操作："
echo ""
echo "1️⃣  如果 Docker Desktop 还未启动，运行:"
echo "   open -a Docker"
echo ""
echo "2️⃣  等待 Docker 完全启动后，开始构建 RustDesk:"
echo "   cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client"
echo "   ./docker-build.sh build"
echo ""
echo "3️⃣  启动容器并编译:"
echo "   ./docker-build.sh start"
echo "   ./docker-build.sh compile"
echo ""
echo "📖 详细文档: DOCKER_INSTALL.md"
echo ""
echo "========================================"
