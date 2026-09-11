# Docker 构建问题解决方案

## 当前问题

Docker 镜像构建时遇到网络问题：
1. ✅ Ubuntu 基础镜像 - 已解决（使用国内镜像源）
2. ✅ 系统依赖包安装 - 已解决（使用阿里云镜像）
3. ✅ Rust 工具链 - 已解决（使用 rsproxy.cn）
4. ❌ Flutter SDK 下载 - **失败**（文件太大 ~700MB，连接不稳定）

## 解决方案

### 方案 1: 使用精简版 Dockerfile（推荐）

如果你只需要构建后端（不需要 GUI），使用精简版：

```bash
# 使用精简版 Dockerfile
docker-compose build -f docker-compose.minimal.yml

# 或者直接构建
docker build -f Dockerfile.minimal -t rustdesk-builder .
```

**优势**：
- 构建快（~10-15 分钟）
- 镜像小（~2GB vs ~5GB）
- 不依赖 Flutter（避免网络问题）
- 可以构建后端核心功能

### 方案 2: 手动下载 Flutter 后构建

如果需要完整的 GUI 构建：

```bash
# 1. 手动下载 Flutter
cd ~/Downloads
wget https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz

# 2. 将文件放到项目目录
cp flutter_linux_3.19.0-stable.tar.xz /Volumes/拓展盘/软件/远程二开项目/rustdesk-client/

# 3. 修改 Dockerfile 使用本地文件
# （我可以帮你修改）

# 4. 重新构建
./docker-build.sh build
```

### 方案 3: 分阶段构建

将构建拆分为多个阶段，每次成功后保存镜像：

```bash
# 阶段 1: 基础镜像 + 系统依赖（已完成）
docker build --target base -t rustdesk-base .

# 阶段 2: 添加 Rust（已完成）
docker build --target rust -t rustdesk-rust .

# 阶段 3: 添加 Flutter（待完成）
docker build --target flutter -t rustdesk-flutter .
```

### 方案 4: 使用已有的 Docker 镜像

使用社区提供的预构建镜像：

```bash
# 拉取 RustDesk 官方构建镜像
docker pull rustdesk/builder:latest

# 或使用其他预配置的 Rust+Flutter 镜像
docker pull ghcr.io/rust-lang/rust:latest
```

## 当前推荐

**建议先使用方案 1（精简版）**，原因：
1. 快速验证环境是否正常
2. 可以先编译后端核心功能
3. 避免网络不稳定的问题
4. 后续可以在容器内手动安装 Flutter

## 下一步操作

你想用哪个方案？

- 方案 1: 精简版（快速，无 Flutter）
- 方案 2: 手动下载 Flutter（完整版）
- 方案 3: 分阶段构建（稳定）
- 方案 4: 使用官方镜像（最快）

或者我们可以继续重试完整版构建，但可能还会遇到同样的网络问题。
