# RustDesk Linux 构建 Docker 镜像
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/opt/vcpkg \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# 配置 Ubuntu 镜像源（使用阿里云镜像）
RUN sed -i 's/ports.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list

# 安装基础工具和依赖（分批安装，减少单次下载量）
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build nasm \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgtk-3-dev libxcb-randr0-dev libxdo-dev \
    libxfixes-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    libasound2-dev libpulse-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    libva-dev libvdpau-dev libclang-dev llvm-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip zip unzip tar \
    && rm -rf /var/lib/apt/lists/*

# 安装 Rust（使用国内镜像）
RUN curl --proto '=https' --tlsv1.2 -sSf https://rsproxy.cn/rustup-init.sh | sh -s -- -y --default-toolchain stable --profile minimal

# 配置 Rust 国内镜像源
RUN mkdir -p /usr/local/cargo && \
    echo '[source.crates-io]' > /usr/local/cargo/config.toml && \
    echo 'replace-with = "rsproxy-sparse"' >> /usr/local/cargo/config.toml && \
    echo '[source.rsproxy]' >> /usr/local/cargo/config.toml && \
    echo 'registry = "https://rsproxy.cn/crates.io-index"' >> /usr/local/cargo/config.toml && \
    echo '[source.rsproxy-sparse]' >> /usr/local/cargo/config.toml && \
    echo 'registry = "sparse+https://rsproxy.cn/index/"' >> /usr/local/cargo/config.toml && \
    echo '[registries.rsproxy]' >> /usr/local/cargo/config.toml && \
    echo 'index = "https://rsproxy.cn/crates.io-index"' >> /usr/local/cargo/config.toml && \
    echo '[net]' >> /usr/local/cargo/config.toml && \
    echo 'git-fetch-with-cli = true' >> /usr/local/cargo/config.toml

# 安装 Flutter（使用清华镜像，添加重试）
ENV PUB_HOSTED_URL="https://mirrors.tuna.tsinghua.edu.cn/dart-pub" \
    FLUTTER_STORAGE_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/flutter"

RUN wget --tries=3 --timeout=30 --retry-connrefused \
    https://mirrors.tuna.tsinghua.edu.cn/flutter/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz \
    -O /tmp/flutter.tar.xz || \
    curl -L --retry 3 --retry-delay 5 \
    https://storage.flutter-io.cn/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz \
    -o /tmp/flutter.tar.xz

RUN tar xf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz

RUN /opt/flutter/bin/flutter config --no-analytics

RUN /opt/flutter/bin/flutter precache --linux || \
    /opt/flutter/bin/flutter precache

ENV PATH="/opt/flutter/bin:${PATH}"

# 设置 vcpkg（使用 gitee 镜像加速）
RUN git clone https://gitee.com/mirrors/vcpkg.git /opt/vcpkg && \
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
