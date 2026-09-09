# RustDesk 自动构建说明

## 🚀 触发构建

### 方式 1: 推送 Tag（推荐，会创建 Release）
```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### 方式 2: 手动触发（测试用）
1. 进入 GitHub 仓库
2. 点击 "Actions"
3. 选择 "Build RustDesk"
4. 点击 "Run workflow"

## 📦 构建产物

构建完成后会生成以下文件：

| 平台 | 文件名 | 说明 |
|------|--------|------|
| macOS (M 系列) | `RustDesk-vX.X.X-macos-arm64.dmg` | 直接双击安装 |
| Windows | `rustdesk-X.X.X-setup.exe` | 安装程序 |
| Linux | `RustDesk-vX.X.X-linux-x86_64.tar.gz` | 解压后运行 |

## ⏱️ 预计构建时间

- macOS: 约 30-45 分钟
- Windows: 约 25-35 分钟
- Linux: 约 20-30 分钟

总计: **约 1-1.5 小时**

## 🔧 配置说明

### 已配置的服务器信息
- 服务器 IP: `38.76.208.177`
- 公钥: `ORAhZaIHMnWVahYvwtW4x9fhRBLGQR6lcU/2scWP/lo=`

这些信息已硬编码到构建配置中，编译出的客户端会自动连接到你的服务器。

## 📝 版本发布流程

1. 确保代码已提交
   ```bash
   git add .
   git commit -m "feat: 新功能描述"
   ```

2. 创建版本 Tag
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   ```

3. 推送代码和 Tag
   ```bash
   git push origin main
   git push origin v1.0.0
   ```

4. 等待自动构建完成（约 1.5 小时）

5. 到 GitHub Releases 页面下载安装包

## 🛠️ 如果构建失败

查看 GitHub Actions 日志：
1. 进入仓库
2. 点击 "Actions"
3. 点击失败的构建任务
4. 查看红色的步骤日志

常见问题：
- **vcpkg 安装超时**: 重新触发构建
- **Flutter 版本问题**: 检查 Flutter SDK 版本
- **依赖缺失**: 检查系统依赖安装步骤
