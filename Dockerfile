# RustDesk Linux 构建 Docker 镜像
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/opt/vcpkg \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# 安装基础工具和依赖
RUN apt-get update && apt-get install -y \
    git curl wget build-essential pkg-config \
    libssl-dev cmake ninja-build \
    libgtk-3-dev libxcb-randr0-dev libxdo-dev \
    libxfixes-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    libasound2-dev libpulse-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    libva-dev libvdpau-dev \
    libclang-dev llvm-dev nasm \
    python3 python3-pip \
    zip unzip tar \
    && rm -rf /var/lib/apt/lists/*

# 安装 Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

# 安装 Flutter
RUN wget -q https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz -O /tmp/flutter.tar.xz && \
    tar xf /tmp/flutter.tar.xz -C /opt && \
    rm /tmp/flutter.tar.xz && \
    /opt/flutter/bin/flutter config --no-analytics && \
    /opt/flutter/bin/flutter precache

ENV PATH="/opt/flutter/bin:${PATH}"

# 设置 vcpkg
RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg && \
    /opt/vcpkg/bootstrap-vcpkg.sh && \
    /opt/vcpkg/vcpkg install libvpx libyuv opus

# 创建工作目录
WORKDIR /workspace

# 验证安装
RUN rustc --version && \
    cargo --version && \
    flutter --version && \
    /opt/vcpkg/vcpkg list

# 构建脚本
COPY <<'EOF' /usr/local/bin/build-rustdesk.sh
#!/bin/bash
set -e

echo "🚀 开始构建 RustDesk..."

if [ ! -d "/workspace/build.py" ]; then
    echo "❌ 错误: 未找到 build.py，请确保挂载了正确的源代码目录"
    exit 1
fi

export VCPKG_ROOT=/opt/vcpkg

echo "📦 更新 Rust 依赖..."
cargo update

echo "🔨 开始编译..."
python3 build.py --flutter --hwcodec

echo "✅ 构建完成！"
echo "📂 输出文件位于: target/release/"
ls -lh target/release/rustdesk 2>/dev/null || echo "⚠️  未找到构建产物"
EOF

RUN chmod +x /usr/local/bin/build-rustdesk.sh

CMD ["/bin/bash"]
