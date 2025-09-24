#!/bin/bash

set -e

trap 'err_line=$LINENO; \
echo "Error occurred at line $err_line. Opening a new terminal for remaining steps."; \
gnome-terminal -- bash -c "echo \"Continuing setup from line $err_line...\"; tail -n +$err_line \"$0\" | bash"; \
exit 1' ERR
first_update()
{
echo "Updating system, will be prompted for password"
sudo apt update && sudo apt upgrade -y
}
firewall()
{echo "Installing and pre-configuring UFW"
sudo apt install -y ufw
sudo ufw enable
sudo ufw default deny incoming 
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
echo "Base UFW rules set"    
}
base_tools()
{
echo "Adding base tools"
echo "Adding cURL, wget, CA-certificates,Gnu Privacy guard etc"
sudo apt update
sudo apt install -y build-essential git curl wget ca-certificates software-properties-common apt-transport-https lsb-release gnupg
}
base_monitoring_tools()
{
echo "adding base monitoring tools"
sudo apt install -y htop iotop iftop net-tools
echo "Base toolkit installed"
echo "Adding Python toolbox"
sudo apt install -y python3 python3-venv python3-pip python3-dev
echo "Python installed"
echo "Installing Docker as per the official way, removes previous Docker install"
}
docker_install()
{
sudo apt remove -y docker docker-engine docker.io containerd runc || true
sudo apt update
sudo install -d -m 0755 -o root -g root /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG kvm $USER
sudo usermod -aG docker $USER
echo "Docker and tools installed"
}
ssh_deploymenr()
{
echo "Adding OpenSSH server"
sudo apt update
sudo apt install -y openssh-server
}
nginx_insyall()
{
echo "Installing and deploying Nginx"
sudo apt install -y nginx
sudo systemctl enable nginx --now
echo "Nginx added and running"
}
fail2ban_install()
{
echo "Adding fail2ban"
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
}
timer_tool()
{
echo "Installing time sync tools for auth"
sudo apt install -y chrony
sudo systemctl enable --now chrony
sudo chronyc tracking
}
cleanup()
{
sudo apt update && sudo apt upgrade -y && sudo apt --autoremove -y
echo "Setup script completed"
}