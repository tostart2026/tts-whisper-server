# 安装必要工具
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# 创建 keyrings 目录
sudo mkdir -p /etc/apt/keyrings

# 下载并转换 Docker 的 GPG 密钥（使用更可靠的 curl 方式）
curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 获取系统版本代号（如 noble）
DISTRO=$(lsb_release -cs)

# 添加源，并明确指定 signed-by 路径
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $DISTRO stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null


sudo apt autoremove -y
sudo apt update   # 此时不应该再出现 “not signed” 错误
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


sudo usermod -aG docker $USER
newgrp docker

