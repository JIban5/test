# GitHub Actions 自动构建指南

## 当前配置状态

### ✅ 已配置的内容

1. **工作流文件**: `.github/workflows/flutter-build.yml` 已存在
2. **Git 远程仓库**: `https://github.com/JIban5/test.git`
3. **当前分支**: `main`

### 📦 构建目标

当前 GitHub Actions 配置支持：
- **Windows x64** (Flutter 版本) - ✅ 已启用
- **Windows ARM64** - ❌ 已禁用（加速构建）
- **Windows x86** (Sciter 版本) - ❌ 已禁用
- **macOS** - ❌ 已禁用
- **Linux** - ❌ 已禁用
- **Android** - ❌ 已禁用

---

## 快速启动自动构建

### 方式 1: 推送代码触发自动构建

```bash
cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client

# 1. 提交所有修改
git add -A
git commit -m "feat: 实现所有自定义功能

- 安装后不自动弹窗、无托盘图标
- Ctrl+Alt+J 全局热键调出设置界面
- 鼠标移动添加随机抖动和停顿
- 网络状态自动检测和重连
- 一键卸载功能
- 安装完成后自动清除桌面快捷方式
- 禁用日志文件生成到磁盘"

# 2. 推送到 GitHub
git push origin main

# 3. 查看构建进度
# 访问: https://github.com/JIban5/test/actions
```

### 方式 2: 手动触发构建（需要配置）

如果需要手动触发构建，需要在 `.github/workflows/flutter-build.yml` 中添加：

```yaml
on:
  workflow_dispatch:  # 添加这一行启用手动触发
  workflow_call:
    inputs:
      # ... 现有配置
```

---

## 构建流程说明

### 1. 触发条件

当前工作流通过 `workflow_call` 触发，这意味着它需要被其他工作流调用。如果你想要：

#### A. 推送代码时自动构建

需要修改触发器：

```yaml
on:
  push:
    branches:
      - main
    paths-ignore:
      - '**.md'
      - 'docs/**'
  pull_request:
    branches:
      - main
```

#### B. 定时构建

```yaml
on:
  schedule:
    - cron: '0 2 * * *'  # 每天凌晨 2 点构建
```

### 2. 构建步骤（Windows x64）

1. **环境准备**
   - Checkout 代码（包含子模块）
   - 安装 LLVM 15.0.6
   - 安装 Flutter 3.24.5
   - 安装 Rust 1.75

2. **依赖安装**
   - 使用 vcpkg 安装 C/C++ 依赖（opus, libvpx, libyuv 等）
   - 配置 vcpkg 缓存加速

3. **编译 RustDesk**
   ```bash
   python3 build.py --portable --flutter --skip-portable-pack --hwcodec --vram
   ```

4. **打包**
   - 生成 `.exe` 自解压安装包
   - 生成 `.msi` Windows 安装程序

5. **签名（可选）**
   - 如果配置了签名密钥，会自动签名

6. **发布**
   - 上传构建产物到 Release（nightly tag）

---

## 修改构建配置

### 启用推送时自动构建

编辑 `.github/workflows/flutter-build.yml`：

```yaml
name: Build the flutter version of the RustDesk

on:
  # 添加推送触发
  push:
    branches:
      - main
  # 保留原有的 workflow_call
  workflow_call:
    inputs:
      upload-artifact:
        type: boolean
        default: true
      upload-tag:
        type: string
        default: "nightly"

# ... 其余配置不变
```

### 启用更多平台构建

如果需要构建 macOS 或 Linux 版本，需要：

1. 找到对应的 job 定义（如 `build-for-macos`）
2. 移除 `if: false` 这一行
3. 确保有足够的 GitHub Actions 配额

---

## 构建产物位置

构建完成后，产物会上传到：

### GitHub Release

- **位置**: `https://github.com/JIban5/test/releases/tag/nightly`
- **文件**:
  - `rustdesk-1.4.9-x86_64.exe` - 自解压安装包
  - `rustdesk-1.4.9-x86_64.msi` - MSI 安装程序

### GitHub Artifacts

如果不发布 Release，可以在 Actions 页面下载：
- **位置**: `https://github.com/JIban5/test/actions`
- **Artifact 名称**: `rustdesk-unsigned-windows-x86_64`

---

## 常见问题

### 1. 构建失败：vcpkg 依赖安装错误

**原因**: vcpkg 版本不匹配或网络问题

**解决方案**:
```yaml
# 检查 VCPKG_COMMIT_ID 是否最新
env:
  VCPKG_COMMIT_ID: "120deac3062162151622ca4860575a33844ba10b"
```

### 2. 构建失败：Flutter 版本问题

**原因**: Flutter SDK 不兼容

**解决方案**:
```yaml
env:
  FLUTTER_VERSION: "3.24.5"  # 使用稳定版本
```

### 3. 构建失败：Rust 编译错误

**原因**: 
- 代码语法错误
- 依赖版本冲突

**解决方案**:
```bash
# 本地先测试编译
cargo check
cargo build --release
```

### 4. 构建时间过长

**优化方案**:
- 禁用不需要的平台构建
- 使用缓存（已配置 `Swatinem/rust-cache`）
- 减少构建 feature（移除 `--vram` 如果不需要）

### 5. Actions 配额不足

**GitHub Free 限制**:
- 公开仓库：无限制
- 私有仓库：2000 分钟/月

**解决方案**:
- 使用自托管 Runner
- 升级到 GitHub Pro
- 优化构建流程减少时间

---

## 自托管 Runner（高级）

如果需要更快的构建速度或私有环境，可以配置自托管 Runner：

### 设置步骤

1. **在 GitHub 仓库中添加 Runner**
   - 进入 `Settings` → `Actions` → `Runners` → `New self-hosted runner`
   - 选择操作系统（Windows）

2. **在本地机器上安装**
   ```powershell
   # Windows PowerShell
   mkdir actions-runner && cd actions-runner
   Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-win-x64-2.311.0.zip -OutFile actions-runner-win-x64-2.311.0.zip
   Expand-Archive -Path actions-runner-win-x64-2.311.0.zip -DestinationPath .
   ./config.cmd --url https://github.com/JIban5/test --token YOUR_TOKEN
   ./run.cmd
   ```

3. **修改工作流使用自托管 Runner**
   ```yaml
   jobs:
     build-for-windows-flutter:
       runs-on: self-hosted  # 改为 self-hosted
   ```

---

## 监控构建状态

### 1. 添加构建状态徽章

在 `README.md` 中添加：

```markdown
[![Build Status](https://github.com/JIban5/test/actions/workflows/flutter-build.yml/badge.svg)](https://github.com/JIban5/test/actions)
```

### 2. 配置通知

在 GitHub 设置中：
- `Settings` → `Notifications` → `Actions`
- 选择通知方式（邮件、Web、手机应用）

### 3. 查看构建日志

```bash
# 使用 GitHub CLI
gh run list
gh run view <run-id> --log
```

---

## 下一步操作

### 立即启动自动构建

```bash
# 1. 提交并推送代码
cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client
git add -A
git commit -m "feat: 实现所有自定义功能"
git push origin main

# 2. 修改工作流启用推送触发（可选）
# 编辑 .github/workflows/flutter-build.yml
# 添加 push 触发器

# 3. 查看构建进度
echo "访问: https://github.com/JIban5/test/actions"
```

### 测试本地构建

在推送到 GitHub 之前，建议本地测试：

```bash
# 检查语法
cargo check

# 完整构建
cargo build --release --features flutter,hwcodec

# 如果成功，再推送到 GitHub
git push origin main
```

---

## 总结

✅ **已准备就绪**:
- GitHub Actions 工作流已配置
- Windows x64 构建已启用
- 所有功能代码已修改完成

🚀 **下一步**:
1. 提交代码到 GitHub
2. 等待自动构建完成（约 30-45 分钟）
3. 从 Release 或 Artifacts 下载安装包
4. 测试所有功能

📊 **构建时间估算**:
- Windows x64: ~30-45 分钟
- 包含缓存后: ~15-25 分钟

---

**最后更新**: 2026-09-11
**仓库**: https://github.com/JIban5/test
**工作流**: flutter-build.yml
