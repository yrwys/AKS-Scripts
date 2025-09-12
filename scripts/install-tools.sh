#!/bin/bash
set -euo pipefail

echo "🚀 Installing Prerequisite Tools..."

# --------------------------------------
# 0️⃣ Install base dependencies
# --------------------------------------
echo -e "\n🔹 Installing base dependencies..."
sudo apt update -y
sudo apt install -y curl wget tar apt-transport-https gnupg lsb-release

# --------------------------------------
# 1️⃣ Install talosctl
# --------------------------------------
echo -e "\n🔹 Installing talosctl..."
curl -sL https://talos.dev/install | sh

# --------------------------------------
# 2️⃣ Install kubectl
# --------------------------------------
echo -e "\n🔹 Installing kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# --------------------------------------
# 3️⃣ Install Helm
# --------------------------------------
echo -e "\n🔹 Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

# --------------------------------------
# 4️⃣ Install Cilium CLI
# --------------------------------------
echo -e "\n🔹 Installing Cilium CLI..."
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
wget "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz"
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz

# --------------------------------------
# 5️⃣ Install k9s
# --------------------------------------
echo -e "\n🔹 Installing k9s..."
wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb && apt install ./k9s_linux_amd64.deb && rm k9s_linux_amd64.deb && rm LICENSE

# --------------------------------------
# 6️⃣ Install kubectx
# --------------------------------------
echo -e "\n🔹 Installing kubectx & kubens..."
KUBECTX_VERSION=$(curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest \
  | grep tag_name | cut -d '"' -f 4)
curl -LO "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_x86_64.tar.gz"
tar -xzf "kubectx_${KUBECTX_VERSION}_linux_x86_64.tar.gz"
sudo mv kubectx /usr/local/bin/
rm "kubectx_${KUBECTX_VERSION}_linux_x86_64.tar.gz"

echo -e "\n✅ All tools installed successfully!"