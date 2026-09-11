# 🚀 GitHub Actions 自动构建 - 快速开始

## 立即开始构建

### 方式 1: 使用一键脚本（推荐）

```bash
cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client
./auto-build.sh
```

脚本会自动：
1. ✅ 检查工作区状态
2. ✅ 提交所有修改
3. ✅ 推送到 GitHub
4. ✅ 触发自动构建

### 方式 2: 手动命令

```bash
cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client

# 1. 提交代码
git add -A
git commit -m "feat: 实现所有自定义功能"

# 2. 推送触发构建
git push origin main
```

### 方式 3: 使用 GitHub 网页手动触发

1. 访问 https://github.com/JIban5/test/actions
2. 选择 "Build the flutter version of the RustDesk"
3. 点击 "Run workflow" 按钮
4. 点击绿色的 "Run workflow" 确认

---

## 构建进度监控

### 查看构建状态

🌐 **网页方式**:
- 访问：https://github.com/JIban5/test/actions

📱 **命令行方式** (需要 GitHub CLI):
```bash
# 安装 GitHub CLI (如果还没有)
brew install gh

# 登录 GitHub
gh auth login

# 查看最新构建
gh run list --limit 5

# 实时监控构建
gh run watch

# 查看构建日志
gh run view --log
```

---

## 下载构建产物

### 方式 1: 从 GitHub Release 下载

构建成功后，产物会发布到：
- **地址**: https://github.com/JIban5/test/releases/tag/nightly

**文件列表**:
- `rustdesk-1.4.9-x86_64.exe` - 自解压安装包（推荐）
- `rustdesk-1.4.9-x86_64.msi` - MSI 安装程序

### 方式 2: 从 Actions Artifacts 下载

如果不想等待 Release 发布：
1. 访问 https://github.com/JIban5/test/actions
2. 点击最新的成功构建
3. 滚动到底部的 "Artifacts" 部分
4. 下载 `rustdesk-unsigned-windows-x86_64.zip`

### 方式 3: 使用命令行下载（需要 GitHub CLI）

```bash
# 下载最新 Release
gh release download nightly -p "rustdesk-*.exe" -p "rustdesk-*.msi"

# 或下载 Artifacts
gh run download <run-id>
```

---

## 构建时间估算

| 构建阶段 | 时间 | 说明 |
|---------|------|------|
| 环境准备 | 3-5 分钟 | 安装 Rust、Flutter、vcpkg |
| 依赖安装 | 10-15 分钟 | vcpkg 安装 C/C++ 库 |
| Rust 编译 | 15-20 分钟 | cargo build --release |
| Flutter 编译 | 3-5 分钟 | flutter build windows |
| 打包签名 | 2-3 分钟 | 生成 exe 和 msi |
| **总计** | **30-45 分钟** | 首次构建，缓存后可减少 50% |

---

## 已配置的触发条件

✅ **自动触发**:
- ✅ 推送到 `main` 分支
- ✅ 排除 `.md` 文档修改
- ✅ 排除 `docs/` 目录修改

✅ **手动触发**:
- ✅ GitHub 网页 "Run workflow" 按钮
- ✅ GitHub CLI: `gh workflow run flutter-build.yml`

---

## 当前构建配置

### 启用的平台
- ✅ **Windows x64** (Flutter + Hardware Codec + VRAM)

### 禁用的平台（可根据需要启用）
- ❌ Windows ARM64
- ❌ Windows x86 (Sciter)
- ❌ macOS
- ❌ Linux
- ❌ Android

### 构建 Features
- ✅ `--flutter` - 使用 Flutter UI
- ✅ `--hwcodec` - 硬件编解码
- ✅ `--vram` - VRAM 支持（NVENC）
- ✅ `--portable` - 便携式安装

---

## 常见问题

### ❓ 构建失败了怎么办？

1. **查看错误日志**
   ```bash
   gh run view --log
   ```

2. **常见错误**:
   - ❌ Rust 编译错误 → 本地先运行 `cargo check`
   - ❌ vcpkg 依赖失败 → 检查网络连接
   - ❌ Flutter 版本问题 → 检查 FLUTTER_VERSION

3. **重新触发构建**
   ```bash
   git commit --allow-empty -m "chore: 重新触发构建"
   git push origin main
   ```

### ❓ 如何加速构建？

1. **使用缓存** - 已自动启用 Rust 和 vcpkg 缓存
2. **禁用不需要的平台** - 只保留 Windows x64
3. **使用自托管 Runner** - 见 `GITHUB_ACTIONS_BUILD.md`

### ❓ 如何修改版本号？

编辑 `Cargo.toml`:
```toml
[package]
version = "1.4.9"  # 修改这里
```

提交后版本号会自动更新到构建产物名称中。

### ❓ 如何启用其他平台构建？

编辑 `.github/workflows/flutter-build.yml`，找到对应的 job（如 `build-for-macos`），移除 `if: false` 这一行。

---

## 验证构建产物

下载构建产物后，测试所有功能：

### ✅ 功能测试清单

1. **安装测试**
   - [ ] 运行 Setup.exe 安装
   - [ ] 安装后无主窗口弹出
   - [ ] 安装后无托盘图标

2. **热键测试**
   - [ ] 按 `Ctrl+Alt+J` 调出设置界面
   - [ ] 可以看到【已上线/未上线】状态
   - [ ] 关闭界面后托盘图标自动隐藏

3. **远程控制测试**
   - [ ] 主控端可查看被控端屏幕
   - [ ] 鼠标操作有随机抖动
   - [ ] 键盘指令正常工作

4. **网络测试**
   - [ ] 断开网络后显示【未上线】
   - [ ] 网络恢复后自动重连到【已上线】

5. **卸载测试**
   - [ ] 点击卸载后进程终止
   - [ ] 自启项清除
   - [ ] 安装目录完全删除

6. **其他测试**
   - [ ] 桌面快捷方式已清除
   - [ ] 后台运行无日志文件生成

---

## 下一步

### 现在就开始构建！

```bash
# 进入项目目录
cd /Volumes/拓展盘/软件/远程二开项目/rustdesk-client

# 运行一键构建脚本
./auto-build.sh

# 或者手动推送
git add -A
git commit -m "feat: 实现所有自定义功能"
git push origin main
```

### 监控构建进度

```bash
# 打开浏览器查看
open https://github.com/JIban5/test/actions

# 或使用命令行
gh run watch
```

### 下载并测试

```bash
# 构建完成后下载
open https://github.com/JIban5/test/releases/tag/nightly

# 或使用命令行
gh release download nightly
```

---

## 技术支持

- 📖 详细文档: `GITHUB_ACTIONS_BUILD.md`
- 📝 功能说明: `功能实现总结.md`
- 🔧 代码修改: `CHANGES.md`
- 🐛 问题反馈: https://github.com/JIban5/test/issues

---

**最后更新**: 2026-09-11  
**准备就绪**: ✅ 可以立即开始构建！
