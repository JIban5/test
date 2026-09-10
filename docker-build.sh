#!/bin/bash
# RustDesk Docker 本地构建脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# 显示帮助信息
show_help() {
    cat << EOF
🚀 RustDesk Docker 本地构建工具

用法:
    ./docker-build.sh [命令] [选项]

命令:
    build       构建 Docker 镜像
    start       启动构建容器
    compile     在容器中编译 RustDesk
    shell       进入容器的交互式 Shell
    clean       清理构建缓存和容器
    logs        查看容器日志
    stop        停止容器
    help        显示此帮助信息

选项:
    --no-cache  构建镜像时不使用缓存
    --release   发布模式构建（默认）
    --debug     调试模式构建

示例:
    # 首次使用：构建镜像
    ./docker-build.sh build

    # 启动容器并编译
    ./docker-build.sh start
    ./docker-build.sh compile

    # 进入容器调试
    ./docker-build.sh shell

    # 清理所有缓存
    ./docker-build.sh clean

EOF
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo_error "Docker 未安装，请先安装 Docker"
        echo_info "访问: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo_error "Docker daemon 未运行，请启动 Docker"
        exit 1
    fi
    
    echo_success "Docker 环境检查通过"
}

# 构建 Docker 镜像
build_image() {
    echo_info "开始构建 Docker 镜像..."
    
    local cache_flag=""
    if [[ "$1" == "--no-cache" ]]; then
        cache_flag="--no-cache"
        echo_warning "使用 --no-cache 模式，将不使用缓存"
    fi
    
    docker-compose build $cache_flag
    
    echo_success "Docker 镜像构建完成！"
}

# 启动容器
start_container() {
    echo_info "启动构建容器..."
    docker-compose up -d
    echo_success "容器已启动"
    
    echo_info "等待容器初始化..."
    sleep 2
    
    docker-compose ps
}

# 编译 RustDesk
compile_rustdesk() {
    echo_info "开始编译 RustDesk..."
    
    if ! docker-compose ps | grep -q "Up"; then
        echo_warning "容器未运行，正在启动..."
        start_container
    fi
    
    local build_mode="release"
    if [[ "$1" == "--debug" ]]; then
        build_mode="debug"
        echo_info "使用调试模式构建"
    fi
    
    echo_info "执行构建命令..."
    docker-compose exec rustdesk-builder /bin/bash -c "
        export VCPKG_ROOT=/opt/vcpkg
        export VCPKG_INSTALLED_ROOT=/opt/vcpkg/installed
        
        echo '📦 更新 Cargo 依赖...'
        cargo update
        
        echo '🔨 开始编译...'
        if [ '$build_mode' == 'release' ]; then
            python3 build.py --flutter --hwcodec
        else
            cargo build
        fi
        
        echo '✅ 编译完成！'
        ls -lh target/$build_mode/rustdesk 2>/dev/null || echo '⚠️  未找到构建产物'
    "
    
    echo_success "编译完成！输出文件在 target/$build_mode/ 目录"
}

# 进入容器 Shell
enter_shell() {
    echo_info "进入容器交互式 Shell..."
    
    if ! docker-compose ps | grep -q "Up"; then
        echo_warning "容器未运行，正在启动..."
        start_container
    fi
    
    docker-compose exec rustdesk-builder /bin/bash
}

# 清理
clean_all() {
    echo_warning "这将删除所有构建缓存和容器"
    read -p "确认继续？(y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo_info "停止并删除容器..."
        docker-compose down -v
        
        echo_info "删除 Docker 镜像..."
        docker rmi rustdesk-client_rustdesk-builder 2>/dev/null || true
        
        echo_success "清理完成！"
    else
        echo_info "已取消"
    fi
}

# 查看日志
show_logs() {
    docker-compose logs -f rustdesk-builder
}

# 停止容器
stop_container() {
    echo_info "停止容器..."
    docker-compose stop
    echo_success "容器已停止"
}

# 主逻辑
main() {
    check_docker
    
    case "${1:-help}" in
        build)
            build_image "$2"
            ;;
        start)
            start_container
            ;;
        compile)
            compile_rustdesk "$2"
            ;;
        shell)
            enter_shell
            ;;
        clean)
            clean_all
            ;;
        logs)
            show_logs
            ;;
        stop)
            stop_container
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
