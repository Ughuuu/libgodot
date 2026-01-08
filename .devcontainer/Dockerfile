FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install basic build tools and dependencies
RUN apt-get update && apt-get install -y --fix-broken \
	# Build essentials
	build-essential \
	gcc \
	g++ \
	make \
	cmake \
	pkg-config \
	# ARM Linux cross-compilation toolchains
	gcc-aarch64-linux-gnu \
	g++-aarch64-linux-gnu \
	gcc-arm-linux-gnueabihf \
	g++-arm-linux-gnueabihf \
	binutils-aarch64-linux-gnu \
	binutils-arm-linux-gnueabihf \
	# Python and SCons
	python3 \
	python3-pip \
	python3-dev \
	# Git and version control
	git \
	curl \
	wget \
	# X11 development libraries
	libx11-dev \
	libxcursor-dev \
	libxinerama-dev \
	libxext-dev \
	libxrandr-dev \
	libxrender-dev \
	libxi-dev \
	libxss-dev \
	libxxf86vm-dev \
	# Wayland development libraries
	libwayland-dev \
	libwayland-egl1 \
	wayland-protocols \
	libdecor-0-dev \
	# Audio libraries
	libasound2-dev \
	libpulse-dev \
	# Graphics libraries
	libvulkan-dev \
	vulkan-tools \
	libgl1-mesa-dev \
	libglu1-mesa-dev \
	# Font and text rendering
	libfontconfig1-dev \
	libfreetype6-dev \
	libharfbuzz-dev \
	libicu-dev \
	# Image libraries
	libpng-dev \
	libjpeg-dev \
	libwebp-dev \
	# Network and compression
	libenet-dev \
	libzstd-dev \
	libbrotli-dev \
	# Other dependencies
	libdbus-1-dev \
	libspeechd-dev \
	libxkbcommon-dev \
	libudev-dev \
	libssl-dev \
	libmbedtls-dev \
	libwslay-dev \
	libminiupnpc-dev \
	libpcre2-dev \
	zlib1g-dev \
	# Utilities
	sudo \
	bash \
	ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

# Install clang separately to avoid python-clang conflicts
# Hold conflicting python-clang packages to prevent installation
RUN apt-get update && \
	apt-mark hold python3-clang-* 2>/dev/null || true && \
	apt-get install -y \
	clang \
	clang++ \
	|| (apt-get install -f -y && apt-get install -y clang clang++) && \
	apt-mark unhold python3-clang-* 2>/dev/null || true && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/*

# Install SCons system-wide
RUN pip3 install scons

# Create a non-root user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
	&& useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
	&& echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
	&& chmod 0440 /etc/sudoers.d/$USERNAME

# Set working directory (user will be set by devcontainer.json remoteUser)
WORKDIR /workspace

