# Docker 文件共享问题解决方案

## 问题诊断

当前遇到的问题：Docker 容器无法访问外部磁盘 `/Volumes/拓展盘/`

这是因为 Docker Desktop for Mac 默认只能访问以下目录：
- `/Users`
- `/tmp`
- `/private`

外部磁盘（如 `/Volumes/拓展盘/`）需要手动授权。

## 解决方案

### 方案 1: 配置 Docker Desktop 文件共享（推荐）

1. **打开 Docker Desktop 设置**
   - 点击右上角 Docker 图标
   - 选择 `Settings` / `Preferences`

2. **配置文件共享**
   - 进入 `Resources` → `File Sharing`
   - 点击 `+` 按钮
   - 添加路径: `/Volumes/拓展盘`
   - 点击 `Apply & Restart`

3. **等待 Docker 重启**（约 10-20 秒）

4. **验证配置**
   ```bash
   cd "/Volumes/拓展盘/软件/远程二开项目/rustdesk-client"
   docker run --rm -v "$(pwd):/workspace" -w /workspace ubuntu:22.04 ls -la
   ```

### 方案 2: 将项目移动到 ~/Documents 或 ~/Desktop

如果文件共享配置不生效，可以将项目移到 Docker 默认可访问的目录：

```bash
# 移动项目到用户目录
cp -r "/Volumes/拓展盘/软件/远程二开项目/rustdesk-client" ~/Documents/

# 切换到新目录
cd ~/Documents/rustdesk-client

# 重新构建和编译
docker-compose -f docker-compose.minimal.yml build
docker-compose -f docker-compose.minimal.yml up -d
```

### 方案 3: 使用软链接

创建软链接到 Docker 可访问的目录：

```bash
# 在用户目录创建软链接
ln -s "/Volumes/拓展盘/软件/远程二开项目/rustdesk-client" ~/rustdesk-client

# 使用软链接目录
cd ~/rustdesk-client
docker run --rm -v "$(pwd):/workspace" -w /workspace ubuntu:22.04 ls -la
```

**注意**: 软链接可能在某些情况下不工作。

### 方案 4: 在容器内直接 git clone（最可靠）

如果以上方案都不行，可以在容器内部克隆代码：

```bash
# 启动容器
docker run -it --rm \
  -v rustdesk-cargo-cache:/usr/local/cargo/registry \
  -v rustdesk-cargo-git-cache:/usr/local/cargo/git \
  rustdesk-client-rustdesk-builder-minimal \
  bash

# 在容器内执行：
cd /tmp
git clone https://github.com/rustdesk/rustdesk.git
cd rustdesk
cargo build --release --bin rustdesk

# 编译完成后，将产物复制出来
# 在另一个终端：
docker cp <container_id>:/tmp/rustdesk/target/release/rustdesk ./
```

## 当前推荐操作

由于你的项目在外部磁盘，我建议：

**优先尝试方案 1**（配置文件共享），步骤：
1. 打开 Docker Desktop → Settings → Resources → File Sharing
2. 添加 `/Volumes/拓展盘`
3. Apply & Restart
4. 重新运行构建命令

**如果方案 1 失败，使用方案 2**（移动项目到 ~/Documents）

## 验证步骤

配置完成后，运行以下命令验证：

```bash
# 测试 Docker 是否能访问目录
cd "/Volumes/拓展盘/软件/远程二开项目/rustdesk-client"
docker run --rm -v "$(pwd):/test" ubuntu:22.04 ls -la /test

# 如果看到文件列表，说明配置成功
```

## 自动化脚本

我还创建了一个自动检测和修复脚本：

```bash
./docker-build.sh check-mount
```

---

**需要我帮你执行哪个方案？**

1. 等你手动配置 Docker Desktop 文件共享
2. 将项目复制到 ~/Documents
3. 在容器内 git clone（最可靠但需要重新下载代码）
