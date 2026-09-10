# Docker 本地构建指南

使用 Docker 在本地快速构建 RustDesk，无需手动配置复杂的开发环境。

## 🚀 快速开始

### 1. 首次使用

```bash
# 构建 Docker 镜像（首次需要 10-20 分钟）
./docker-build.sh build

# 启动构建容器
./docker-build.sh start

# 开始编译 RustDesk
./docker-build.sh compile
```

### 2. 后续使用

```bash
# 直接编译（容器会自动启动）
./docker-build.sh compile
```

## 📋 命令说明

| 命令 | 说明 | 示例 |
|------|------|------|
| `build` | 构建 Docker 镜像 | `./docker-build.sh build` |
| `build --no-cache` | 无缓存重新构建 | `./docker-build.sh build --no-cache` |
| `start` | 启动构建容器 | `./docker-build.sh start` |
| `compile` | 编译 RustDesk（release） | `./docker-build.sh compile` |
| `compile --debug` | 编译调试版本 | `./docker-build.sh compile --debug` |
| `shell` | 进入容器 Shell | `./docker-build.sh shell` |
| `logs` | 查看容器日志 | `./docker-build.sh logs` |
| `stop` | 停止容器 | `./docker-build.sh stop` |
| `clean` | 清理所有缓存和容器 | `./docker-build.sh clean` |

## 🎯 使用场景

### 场景 1: 快速编译
```bash
./docker-build.sh compile
```
编译产物位于 `target/release/rustdesk`

### 场景 2: 调试开发
```bash
# 进入容器
./docker-build.sh shell

# 在容器内手动执行命令
cargo build --release
cargo test
python3 build.py --flutter
```

### 场景 3: 清理重建
```bash
# 清理所有缓存
./docker-build.sh clean

# 重新构建
./docker-build.sh build --no-cache
./docker-build.sh compile
```

## 📦 Docker 镜像内容

### 预装工具
- ✅ Rust (stable)
- ✅ Flutter 3.19.0
- ✅ Python 3
- ✅ vcpkg (libvpx, libyuv, opus)
- ✅ LLVM/Clang
- ✅ CMake, Ninja
- ✅ 所有必需的系统库

### 缓存机制
Docker 使用 volume 缓存以下内容，加速后续构建：
- `cargo-cache`: Rust 依赖包
- `cargo-git-cache`: Git 依赖
- `target-cache`: 编译产物

## ⚡ 性能对比

| 构建方式 | 首次构建 | 增量构建 | 清理后重建 |
|---------|---------|---------|------------|
| GitHub Actions | ~30 分钟 | ~30 分钟 | ~30 分钟 |
| 本地 Docker | ~15 分钟 | **~3 分钟** | ~15 分钟 |
| 本地原生 | ~10 分钟 | **~2 分钟** | ~10 分钟 |

**优势**：
- 🚀 增量编译非常快（有缓存）
- 🔒 环境隔离，不污染本地系统
- 🔄 可重现的构建环境
- 🌍 跨平台（macOS/Linux/Windows）

## 🛠️ 高级用法

### 自定义构建参数
```bash
# 进入容器
./docker-build.sh shell

# 使用自定义参数构建
export RUSTFLAGS="-C target-cpu=native"
cargo build --release --features hwcodec

# 只构建后端（不含 Flutter）
cargo build --release --bin rustdesk
```

### 并行构建多个版本
```bash
# 终端 1: 构建 release
./docker-build.sh compile

# 终端 2: 构建 debug
./docker-build.sh shell
cargo build
```

### 查看构建日志
```bash
# 实时查看容器日志
./docker-build.sh logs

# 或者
docker-compose logs -f rustdesk-builder
```

## 🐛 故障排除

### 问题 1: Docker 镜像构建失败
```bash
# 清理并重新构建
docker system prune -a
./docker-build.sh build --no-cache
```

### 问题 2: 编译错误
```bash
# 进入容器检查环境
./docker-build.sh shell

# 验证工具链
rustc --version
cargo --version
flutter --version
/opt/vcpkg/vcpkg list

# 清理 Cargo 缓存
cargo clean
```

### 问题 3: 磁盘空间不足
```bash
# 查看 Docker 占用空间
docker system df

# 清理未使用的资源
docker system prune -a --volumes

# 清理 RustDesk 构建缓存
./docker-build.sh clean
```

### 问题 4: 容器无法启动
```bash
# 查看错误日志
docker-compose logs rustdesk-builder

# 删除并重新创建容器
docker-compose down
docker-compose up -d
```

## 📊 系统要求

- **Docker**: 最新版本
- **磁盘空间**: 至少 20GB 可用
- **内存**: 建议 8GB+
- **CPU**: 多核 CPU 可加速编译

## 🔧 配置文件说明

### Dockerfile
定义构建环境，包含所有必需的工具和依赖。

### docker-compose.yml
定义服务配置和缓存卷挂载策略。

### docker-build.sh
构建管理脚本，提供友好的命令行界面。

## 💡 最佳实践

1. **首次构建后保持容器运行**，避免重复启动开销
2. **使用 volume 缓存**，不要删除 cargo-cache 卷
3. **定期更新依赖**: `./docker-build.sh shell` → `cargo update`
4. **CI/CD 结合**: 本地快速迭代，GitHub Actions 做最终发布

## 🔗 相关资源

- [Docker 官方文档](https://docs.docker.com/)
- [RustDesk 官方仓库](https://github.com/rustdesk/rustdesk)
- [Rust 构建问题修复指南](./Rust构建问题修复指南.md)

---

**提示**: 第一次构建镜像需要下载约 2GB 的依赖，请确保网络稳定。后续构建会使用缓存，速度会快很多！
