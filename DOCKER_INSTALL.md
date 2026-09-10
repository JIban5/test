# Docker 安装和 RustDesk 本地构建完整指南

## 📦 第一步: 安装 Docker Desktop (macOS)

### 方法 1: 官方安装（推荐）

1. **下载 Docker Desktop for Mac**
   - Apple Silicon (M1/M2/M3): https://desktop.docker.com/mac/main/arm64/Docker.dmg
   - Intel 芯片: https://desktop.docker.com/mac/main/amd64/Docker.dmg

2. **安装步骤**
   ```bash
   # 打开下载的 DMG 文件
   # 将 Docker.app 拖到 Applications 文件夹
   # 从应用程序启动 Docker Desktop
   ```

3. **验证安装**
   ```bash
   docker --version
   docker-compose --version
   ```

### 方法 2: 使用 Homebrew

```bash
# 安装 Docker Desktop
brew install --cask docker

# 启动 Docker Desktop（从应用程序或命令行）
open -a Docker

# 等待 Docker 启动完成（右上角菜单栏出现鲸鱼图标）
# 验证安装
docker --version
```

### Docker Desktop 配置建议

在 Docker Desktop 的设置中调整资源：

1. **Resources → Advanced**
   - CPUs: 4-8 核（根据你的 Mac）
   - Memory: 8GB+（推荐 12GB）
   - Swap: 2GB
   - Disk image size: 60GB+

2. **启用 VirtioFS**（macOS 12.5+）
   - 在 General → Use the new Virtualization framework 打勾
   - 这会大幅提升文件 I/O 性能

## 🚀 第二步: 开始构建

### 快速启动（3 步完成）

```bash
# 1. 构建 Docker 镜像（首次约 15-20 分钟）
./docker-build.sh build

# 2. 启动构建容器
./docker-build.sh start

# 3. 编译 RustDesk
./docker-build.sh compile
```

构建完成后，产物在 `target/release/rustdesk`

### 完整构建流程演示

```bash
# 检查 Docker 状态
docker info

# 开始构建
cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client

# 构建镜像（下载依赖并安装工具链）
./docker-build.sh build

# 输出示例：
# ✅ Docker 环境检查通过
# ℹ️  开始构建 Docker 镜像...
# [+] Building 1234.5s (15/15) FINISHED
# ✅ Docker 镜像构建完成！

# 启动容器
./docker-build.sh start

# 编译代码
./docker-build.sh compile

# 输出示例：
# ℹ️  开始编译 RustDesk...
# 📦 更新 Cargo 依赖...
# 🔨 开始编译...
# Compiling rustdesk v1.2.3
# ✅ 编译完成！
```

## 🎯 常用操作

### 开发调试

```bash
# 进入容器进行手动操作
./docker-build.sh shell

# 在容器内可以执行：
cargo build --release           # 编译 release 版本
cargo build                     # 编译 debug 版本
cargo test                      # 运行测试
cargo clean                     # 清理构建产物
python3 build.py --flutter      # 完整构建（含 Flutter）
```

### 查看构建状态

```bash
# 查看容器状态
docker-compose ps

# 查看日志
./docker-build.sh logs

# 查看资源使用
docker stats rustdesk-builder
```

### 停止和清理

```bash
# 停止容器（保留缓存）
./docker-build.sh stop

# 完全清理（删除容器和缓存）
./docker-build.sh clean
```

## ⚡ 性能优化技巧

### 1. 使用缓存卷加速编译

Docker 已配置 3 个缓存卷：
- `cargo-cache`: Cargo 依赖包缓存
- `cargo-git-cache`: Git 仓库缓存
- `target-cache`: 编译产物缓存

**首次编译**: ~15 分钟
**增量编译**: ~3-5 分钟（有缓存）

### 2. 保持容器运行

```bash
# 启动后保持容器运行，避免重复启动开销
./docker-build.sh start

# 后续直接编译（容器会自动使用）
./docker-build.sh compile
```

### 3. 并行编译

在容器内设置并行编译数：

```bash
./docker-build.sh shell

# 设置编译并行度（根据你的 CPU 核心数）
export CARGO_BUILD_JOBS=8
cargo build --release
```

### 4. 使用 sccache 缓存（可选）

```bash
# 在容器内安装 sccache
cargo install sccache

# 设置环境变量
export RUSTC_WRAPPER=sccache
export SCCACHE_DIR=/workspace/.sccache

# 编译（会使用 sccache）
cargo build --release

# 查看缓存统计
sccache --show-stats
```

## 📊 构建时间对比

| 环境 | 首次构建 | 增量构建 | 清理后重建 |
|------|---------|---------|-----------|
| GitHub Actions | 30-40 分钟 | 30-40 分钟 | 30-40 分钟 |
| 本地 Docker (无缓存) | 15-20 分钟 | 15-20 分钟 | 15-20 分钟 |
| 本地 Docker (有缓存) | 15-20 分钟 | **3-5 分钟** ⚡ | 15-20 分钟 |
| 本地原生编译 | 10-15 分钟 | **2-3 分钟** 🚀 | 10-15 分钟 |

## 🐛 常见问题

### Q1: Docker 启动失败

```bash
# 检查 Docker Desktop 是否在运行
ps aux | grep -i docker

# 重启 Docker Desktop
killall Docker && open -a Docker
```

### Q2: 磁盘空间不足

```bash
# 查看 Docker 占用
docker system df

# 清理未使用的资源
docker system prune -a --volumes

# 清理 RustDesk 构建缓存
./docker-build.sh clean
```

### Q3: 编译速度慢

```bash
# 1. 增加 Docker Desktop 资源（设置中调整）
# 2. 确保使用了缓存卷
docker volume ls | grep rustdesk

# 3. 检查是否使用了 VirtioFS
# Docker Desktop → Settings → General → Use VirtioFS
```

### Q4: 容器无法访问代码

```bash
# 检查挂载
docker-compose config

# 重新创建容器
docker-compose down
docker-compose up -d
```

## 🔄 CI/CD 结合使用

### 本地开发流程（推荐）

```bash
# 日常开发：使用 Docker 快速迭代
./docker-build.sh compile       # 本地快速验证

# 提交前测试
./docker-build.sh shell
cargo test                      # 运行测试
cargo clippy                    # 代码检查

# 推送到 GitHub
git add .
git commit -m "feature: xxx"
git push

# GitHub Actions 自动构建和发布
```

### 混合构建策略

- **本地 Docker**: 日常开发、快速验证、调试
- **GitHub Actions**: 正式发布、多平台构建、自动化测试

## 📝 文件清单

项目中新增的 Docker 相关文件：

```
rustdesk-client/
├── Dockerfile              # Docker 镜像定义
├── Dockerfile.windows      # Windows 构建镜像（仅供参考）
├── docker-compose.yml      # Docker Compose 配置
├── docker-build.sh         # 构建管理脚本
├── .dockerignore          # Docker 忽略文件
├── DOCKER_BUILD.md        # 详细构建文档
└── DOCKER_INSTALL.md      # 本文件
```

## 🎓 下一步学习

1. **Docker 基础**
   - [Docker 官方教程](https://docs.docker.com/get-started/)
   - [Docker Compose 文档](https://docs.docker.com/compose/)

2. **Rust 构建优化**
   - [Cargo 文档](https://doc.rust-lang.org/cargo/)
   - [构建问题修复指南](./Rust构建问题修复指南.md)

3. **RustDesk 开发**
   - [RustDesk 官方文档](https://rustdesk.com/docs/)
   - [贡献指南](https://github.com/rustdesk/rustdesk/blob/master/CONTRIBUTING.md)

---

## 🆘 需要帮助？

遇到问题时：

1. **检查日志**: `./docker-build.sh logs`
2. **进入容器调试**: `./docker-build.sh shell`
3. **查看系统状态**: `docker system df`, `docker ps`
4. **重新构建**: `./docker-build.sh clean && ./docker-build.sh build --no-cache`

**提示**: 首次构建需要下载大量依赖，请耐心等待。后续构建会使用缓存，速度会快很多！
