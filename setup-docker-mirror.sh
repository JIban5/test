#!/bin/bash
# Docker 镜像加速配置脚本

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo ""
echo "========================================"
echo "  Docker 镜像加速配置"
echo "========================================"
echo ""

# 检查 Docker 是否运行
if ! docker info &> /dev/null; then
    echo_warning "Docker 未运行，请先启动 Docker Desktop"
    exit 1
fi

echo_info "当前 Docker 配置位置: ~/.docker/daemon.json"
echo ""

DAEMON_JSON="$HOME/.docker/daemon.json"
BACKUP_JSON="$HOME/.docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)"

# 备份现有配置
if [ -f "$DAEMON_JSON" ]; then
    echo_warning "发现现有配置，备份到: $BACKUP_JSON"
    cp "$DAEMON_JSON" "$BACKUP_JSON"
fi

# 创建 .docker 目录
mkdir -p "$HOME/.docker"

# 写入新配置
cat > "$DAEMON_JSON" << 'EOF'
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "experimental": false,
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.mirrors.sjtug.sjtu.edu.cn",
    "https://mirror.baidubce.com"
  ]
}
EOF

echo_success "配置文件已写入: $DAEMON_JSON"
echo ""

echo_warning "⚠️  重要：需要重启 Docker Desktop 使配置生效"
echo ""
echo "方法1: 通过命令行重启（推荐）"
echo "--------------------------------------"
echo "killall Docker && open -a Docker"
echo ""
echo "方法2: 手动重启"
echo "--------------------------------------"
echo "1. 右键点击顶部菜单栏的 Docker 图标"
echo "2. 选择 'Quit Docker Desktop'"
echo "3. 重新打开 Docker Desktop"
echo ""

read -p "是否立即重启 Docker Desktop？(y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo_info "正在重启 Docker Desktop..."
    killall Docker 2>/dev/null || true
    sleep 2
    open -a Docker
    
    echo_info "等待 Docker 启动（约 10-20 秒）..."
    for i in {1..30}; do
        if docker info &> /dev/null 2>&1; then
            echo_success "Docker 已启动！"
            break
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    
    # 验证镜像配置
    echo ""
    echo "========================================"
    echo_info "验证镜像加速配置..."
    echo ""
    docker info | grep -A 10 "Registry Mirrors" || echo_warning "未找到镜像配置信息"
    echo ""
    echo "========================================"
    echo_success "配置完成！现在可以继续构建了"
    echo ""
    echo "运行以下命令开始构建："
    echo "  cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client"
    echo "  ./docker-build.sh build"
else
    echo_info "请手动重启 Docker Desktop 后继续"
fi
