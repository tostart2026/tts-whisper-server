#!/bin/bash
# ============================================
# 脚本名称: uninstall_docker.sh
# 功能描述: 彻底卸载 Docker 及所有相关组件
# 适用系统: Ubuntu/Debian, CentOS/RHEL, Fedora
# ============================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统类型"
        exit 1
    fi
    
    log_info "检测到操作系统: $OS $VERSION"
}

# 停止 Docker 服务
stop_docker_services() {
    log_step "停止所有 Docker 服务..."
    
    # 停止 Docker 守护进程
    systemctl stop docker 2>/dev/null || true
    systemctl stop docker.socket 2>/dev/null || true
    systemctl disable docker 2>/dev/null || true
    systemctl disable docker.socket 2>/dev/null || true
    
    # 停止 Docker 容器
    if command -v docker &> /dev/null; then
        docker kill $(docker ps -aq) 2>/dev/null || true
    fi
    
    log_info "Docker 服务已停止"
}

# 卸载 Docker 包
remove_docker_packages() {
    log_step "卸载 Docker 软件包..."
    
    case $OS in
        ubuntu|debian)
            # Ubuntu/Debian 系统
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras 2>/dev/null || true
            apt-get purge -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            ;;
            
        centos|rhel|rocky|almalinux|fedora)
            # RHEL/CentOS/Fedora 系统
            yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras 2>/dev/null || true
            yum remove -y docker docker-common docker-selinux docker-engine 2>/dev/null || true
            dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras 2>/dev/null || true
            dnf remove -y docker docker-common docker-selinux docker-engine 2>/dev/null || true
            ;;
            
        *)
            log_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    log_info "Docker 软件包已卸载"
}

# 删除 Docker 数据和配置文件
remove_docker_data() {
    log_step "删除 Docker 数据和配置文件..."
    
    # 删除 Docker 数据目录（包含镜像、容器、卷等）
    if [[ -d /var/lib/docker ]]; then
        rm -rf /var/lib/docker
        log_info "已删除 /var/lib/docker"
    fi
    
    # 删除容器运行时数据
    if [[ -d /var/lib/containerd ]]; then
        rm -rf /var/lib/containerd
        log_info "已删除 /var/lib/containerd"
    fi
    
    # 删除 BuildKit 缓存
    if [[ -d /var/lib/buildkit ]]; then
        rm -rf /var/lib/buildkit
        log_info "已删除 /var/lib/buildkit"
    fi
    
    # 删除 Docker 配置文件
    if [[ -d /etc/docker ]]; then
        rm -rf /etc/docker
        log_info "已删除 /etc/docker"
    fi
    
    # 删除 Docker 运行时文件
    if [[ -d /run/docker ]]; then
        rm -rf /run/docker
    fi
    
    if [[ -d /run/containerd ]]; then
        rm -rf /run/containerd
    fi
    
    # 删除用户配置
    for user_home in /home/*; do
        if [[ -d "$user_home/.docker" ]]; then
            rm -rf "$user_home/.docker"
            log_info "已删除 $user_home/.docker"
        fi
    done
    
    # 删除 root 用户配置
    if [[ -d /root/.docker ]]; then
        rm -rf /root/.docker
        log_info "已删除 /root/.docker"
    fi
    
    log_info "Docker 数据和配置已清理"
}

# 清理 Docker 相关的 systemd 服务文件
remove_systemd_files() {
    log_step "清理 systemd 服务文件..."
    
    rm -f /etc/systemd/system/docker.service
    rm -f /etc/systemd/system/docker.socket
    rm -f /etc/systemd/system/containerd.service
    rm -f /etc/systemd/system/multi-user.target.wants/docker.service
    rm -f /etc/systemd/system/multi-user.target.wants/docker.socket
    
    # 重新加载 systemd
    systemctl daemon-reload 2>/dev/null || true
    
    log_info "systemd 服务文件已清理"
}

# 清理 Docker 网络配置
remove_network_config() {
    log_step "清理 Docker 网络配置..."
    
    # 删除 Docker 网络接口
    if command -v ip &> /dev/null; then
        ip link del docker0 2>/dev/null || true
        ip link del docker_gwbridge 2>/dev/null || true
    fi
    
    # 删除网络配置文件
    rm -rf /etc/cni 2>/dev/null || true
    rm -rf /opt/cni 2>/dev/null || true
    
    log_info "网络配置已清理"
}

# 清理 PATH 中的 Docker 符号链接
remove_binaries() {
    log_step "清理 Docker 二进制文件..."
    
    # 删除常见的 Docker 可执行文件
    for bin in docker dockerd docker-init docker-proxy containerd containerd-shim containerd-shim-runc-v2 ctr runc; do
        for path in /usr/bin /usr/local/bin /usr/sbin /usr/local/sbin; do
            if [[ -f "$path/$bin" ]]; then
                rm -f "$path/$bin"
                log_info "已删除 $path/$bin"
            fi
        done
    done
    
    log_info "二进制文件已清理"
}

# 显示卸载完成信息
show_completion() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Docker 卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}清理项目:${NC}"
    echo "  - 所有 Docker 软件包"
    echo "  - /var/lib/docker (镜像、容器、卷)"
    echo "  - /var/lib/containerd (容器运行时)"
    echo "  - /etc/docker (配置文件)"
    echo "  - Docker systemd 服务"
    echo "  - Docker 网络配置"
    echo "  - Docker 二进制文件"
    echo "  - 用户配置目录"
    echo ""
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  1. Docker 已彻底卸载，所有容器数据已被删除"
    echo "  2. 如需安装 Docker，请重新运行官方安装脚本"
    echo "  3. 建议重启系统以确保所有内核模块清理干净"
    echo ""
    echo -e "${BLUE}重启命令: ${NC}sudo reboot"
    echo ""
}

# 主函数
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   Docker 完整卸载脚本${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检测操作系统
    detect_os
    
    echo ""
    log_warn "此操作将删除所有 Docker 镜像、容器、卷和配置数据！"
    log_warn "该操作不可恢复，请确认已备份重要数据！"
    echo ""
    
    # 确认操作
    read -p "是否继续卸载 Docker？(输入 yes 确认): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        exit 0
    fi
    
    echo ""
    log_info "开始卸载 Docker..."
    echo ""
    
    # 执行卸载步骤
    stop_docker_services
    remove_docker_packages
    remove_docker_data
    remove_systemd_files
    remove_network_config
    remove_binaries
    
    # 完成
    show_completion
    
    # 询问是否重启
    read -p "是否立即重启系统？(输入 yes 确认): " restart_confirm
    if [[ "$restart_confirm" == "yes" ]]; then
        log_info "系统将在 5 秒后重启..."
        sleep 5
        reboot
    else
        log_info "建议稍后手动重启系统以完成清理"
    fi
}

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 此脚本需要 root 权限运行${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 执行主函数
main "$@"

# 检查 Docker 命令是否存在
which docker

# 检查 Docker 服务状态
systemctl status docker

# 检查数据目录是否已删除
ls -la /var/lib/docker

# 检查 Docker 进程
ps aux | grep docker
