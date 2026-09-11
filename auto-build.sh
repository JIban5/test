#!/bin/bash
# RustDesk 自动构建脚本
# 用途：提交代码并触发 GitHub Actions 自动构建

set -e

echo "=========================================="
echo "RustDesk 自动构建脚本"
echo "=========================================="
echo ""

# 进入项目目录
cd "$(dirname "$0")"

# 1. 检查是否有修改
echo "📝 检查工作区状态..."
if [[ -z $(git status --porcelain) ]]; then
    echo "✅ 工作区干净，无需提交"
else
    echo "📦 发现以下修改："
    git status --short
    echo ""
    
    # 2. 提交所有修改
    read -p "是否提交所有修改？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "💾 提交修改..."
        git add -A
        git commit -m "feat: 实现所有自定义功能

- 安装后不自动弹窗、无托盘图标
- Ctrl+Alt+J 全局热键调出设置界面
- 鼠标移动添加随机抖动和停顿
- 网络状态自动检测和重连
- 一键卸载功能
- 安装完成后自动清除桌面快捷方式
- 禁用日志文件生成到磁盘
- 配置 GitHub Actions 自动构建"
        echo "✅ 提交完成"
    else
        echo "❌ 取消提交"
        exit 1
    fi
fi

echo ""

# 3. 推送到 GitHub
read -p "是否推送到 GitHub 并触发自动构建？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 推送到 GitHub..."
    git push origin main
    echo "✅ 推送完成！"
    echo ""
    echo "=========================================="
    echo "GitHub Actions 构建已触发！"
    echo "=========================================="
    echo ""
    echo "📊 查看构建进度："
    echo "   https://github.com/JIban5/test/actions"
    echo ""
    echo "📦 构建完成后下载产物："
    echo "   https://github.com/JIban5/test/releases/tag/nightly"
    echo ""
    echo "⏱️  预计构建时间: 30-45 分钟"
    echo ""
    echo "💡 提示: 可以使用 'gh run list' 和 'gh run watch' 命令监控构建"
    echo ""
else
    echo "❌ 取消推送"
    exit 1
fi
