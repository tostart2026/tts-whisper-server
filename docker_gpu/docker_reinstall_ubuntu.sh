#!/usr/bin/env bash
#===============================================================================
# Docker 卸载并重装脚本 (Ubuntu)
# 功能: 彻底卸载所有 Docker 相关包 → 清理残留 → 安装 Docker CE + compose 插件
#===============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

#------------------------------------------------------------------------------
# 步骤 0: 权限检查
#------------------------------------------------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    log_error "请使用 sudo 或以 root 身份运行此脚本。"
    exit 1
fi

log_info "开始 Docker 卸载与重装流程..."

#===============================================================================
# 阶段一: 彻底卸载
#===============================================================================
log_info "======================================"
log_info "  阶段一: 卸载现有 Docker 相关包"
log_info "======================================"

# 1.1 停止所有运行中的容器
log_info "停止所有运行中的 Docker 容器..."
docker ps -q 2>/dev/null | xargs -r docker stop 2>/dev/null || true

# 1.2 停止 Docker 服务
log_info "停止 Docker 相关服务..."
systemctl stop docker 2>/dev/null || true
systemctl stop docker.socket 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true

# 1.3 禁用服务
log_info "禁用 Docker 相关服务..."
systemctl disable docker 2>/dev/null || true
systemctl disable docker.socket 2>/dev/null || true
systemctl disable containerd 2>/dev/null || true

# 1.4 卸载所有 Docker 相关包 (覆盖 apt 和 snap 安装的)
log_info "卸载所有 Docker 相关包..."
PACKAGES=(
    docker-ce
    docker-ce-cli
    docker-ce-rootless-extras
    docker-buildx-plugin
    docker-compose-plugin
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    docker-registry
    containerd
    containerd.io
    runc
    podman-docker
)
for pkg in "${PACKAGES[@]}"; do
    if dpkg -l "$pkg" &>/dev/null; then
        log_info "  正在卸载: $pkg"
        apt-get purge -y "$pkg" 2>/dev/null || true
    fi
done

# 1.5 也处理 snap 安装的 docker
if command -v snap &>/dev/null && snap list docker &>/dev/null 2>&1; then
    log_info "卸载 snap 安装的 Docker..."
    snap remove docker 2>/dev/null || true
fi

# 1.6 自动清理
log_info "清理不再需要的依赖包..."
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean -y 2>/dev/null || true

#===============================================================================
# 阶段二: 清理残留
#===============================================================================
log_info "======================================"
log_info "  阶段二: 清理残留数据目录与配置"
log_info "======================================"

DIRS_TO_REMOVE=(
    /var/lib/docker
    /var/lib/containerd
    /var/lib/docker-engine
    /etc/docker
    /etc/containerd
    /var/run/docker.sock
    /var/run/docker
    /run/docker
    ~/.docker
)
for dir in "${DIRS_TO_REMOVE[@]}"; do
    if [[ -e "$dir" ]]; then
        log_warn "  删除: $dir"
        rm -rf "$dir"
    fi
done

# 清理用户级 docker 配置
if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME=$(eval echo "~${SUDO_USER}")
    if [[ -d "$USER_HOME/.docker" ]]; then
        log_warn "  删除: $USER_HOME/.docker"
        rm -rf "$USER_HOME/.docker"
    fi
fi

# 清理 systemd 残留
log_info "重载 systemd 配置..."
systemctl daemon-reload 2>/dev/null || true

#===============================================================================
# 阶段三: 安装 Docker CE
#===============================================================================
log_info "======================================"
log_info "  阶段三: 安装 Docker CE"
log_info "======================================"

# 3.1 安装前置依赖
log_info "安装前置依赖..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# 3.2 添加 Docker GPG 密钥 (阿里云镜像)
log_info "添加 Docker GPG 密钥 (阿里云镜像)..."
install -m 0755 -d /etc/apt/keyrings
# 优先使用阿里云镜像下载 GPG 密钥，解决国内网络无法直连 Docker 官方源的问题
if curl -fsSL --connect-timeout 10 https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
    log_info "GPG 密钥下载成功 (阿里云镜像)"
else
    log_warn "阿里云镜像下载失败，尝试 Docker 官方源..."
    curl -fsSL --connect-timeout 10 https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null \
        || { log_error "GPG 密钥下载失败，请检查网络连接"; exit 1; }
fi
chmod a+r /etc/apt/keyrings/docker.gpg

# 3.3 添加 Docker APT 源 (阿里云镜像)
log_info "配置 Docker APT 源 (阿里云镜像)..."
ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

# 使用阿里云 Docker CE 镜像源，国内网络环境下速度更快更稳定
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

# 3.4 安装 Docker CE 及 compose 插件
log_info "更新 APT 索引并安装 Docker CE + compose 插件..."
apt-get update -y
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

#===============================================================================
# 阶段四: 配置与启动
#===============================================================================
log_info "======================================"
log_info "  阶段四: 启动 Docker 服务"
log_info "======================================"

# 4.1 启动 Docker
log_info "启动 Docker 服务..."
systemctl start docker

# 4.2 设置开机自启
log_info "设置 Docker 开机自启..."
systemctl enable docker
systemctl enable containerd

# 4.3 将当前用户加入 docker 组 (避免每次 sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
    log_info "将用户 ${SUDO_USER} 加入 docker 组..."
    usermod -aG docker "$SUDO_USER"
    log_warn "用户组变更需重新登录或执行 'newgrp docker' 才能生效。"
fi

#===============================================================================
# 阶段五: 验证
#===============================================================================
log_info "======================================"
log_info "  阶段五: 验证安装"
log_info "======================================"

echo ""

# 5.1 版本信息
log_info "Docker 版本:"
docker --version 2>/dev/null || log_error "docker 命令不可用"

echo ""

# 5.2 compose 插件
log_info "Docker Compose 插件版本:"
docker compose version 2>/dev/null || log_error "docker compose 命令不可用"

echo ""

# 5.3 服务状态
log_info "Docker 服务状态:"
systemctl is-active docker 2>/dev/null && log_info "Docker 服务运行中" || log_error "Docker 服务未运行"

echo ""

# 5.4 运行 hello-world 测试
log_info "运行 hello-world 测试容器..."
if docker run --rm hello-world 2>/dev/null; then
    log_info "hello-world 测试通过!"
else
    log_error "hello-world 测试失败，请检查 Docker 安装。"
fi

echo ""
log_info "======================================"
log_info "  安装完成!"
log_info "======================================"
log_info "Docker CE:        $(docker --version 2>/dev/null || echo 'N/A')"
log_info "Docker Compose:   $(docker compose version 2>/dev/null || echo 'N/A')"
log_info ""
if [[ -n "${SUDO_USER:-}" ]]; then
    log_warn "注意: 用户 '${SUDO_USER}' 已被加入 docker 组。"
    log_warn "请 退出终端重新登录 或执行 'newgrp docker' 以使组权限生效，之后即可无需 sudo 运行 docker 命令。"
fi
