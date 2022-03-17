#!/bin/bash

set -e 
set -o pipefail

LIBRARY_PATH="../../lib/"

# source all necessary files
for f in $LIBRARY_PATH*; do
 . $f
done

function phase1() {

stage "Configuring kernel for containerd and k8s"

# Load the br_netfilter module for kubernetes and overlay for the containerd
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

sudo modprobe br_netfilter
sudo modprobe overlay

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

stage "Reload sysctl"

sudo sysctl --system

###### NERDCTL(with Containerd) FULL INSTALLATION ######

stage "Installing required packages for installation process"

sudo apt-get update

# Install the req packages
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

stage "Getting the latest relase of nerdctl with containerd"

# Find the latest release of nerdctl full
LT_RLS="$(get_latest_release_from_github containerd/nerdctl | sed -e "s/v//g")"

# get the nerdctl full binaries
wget https://github.com/containerd/nerdctl/releases/download/v$LT_RLS/nerdctl-full-$LT_RLS-linux-amd64.tar.gz

# extract the archive
sudo tar Cxzvvf /usr/local nerdctl-full-$LT_RLS-linux-amd64.tar.gz

# newuidmap command needed by rootless-install.sh
sudo apt install uidmap

stage "Enabling cgroup v2"

# Enabling cgroup v2 
# To boot the host with cgroup v2, add the following string to the GRUB_CMDLINE_LINUX line in /etc/default/grub and then run `sudo update-grub`.
sudo sed -i "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"systemd.unified_cgroup_hierarchy=1\"/g" /etc/default/grub

stage "Update grub"

sudo update-grub

stage "Enable CPU, CPUSET, and I/O delegation"

# Enabling CPU, CPUSET, and I/O delegation
sudo mkdir -p /etc/systemd/system/user@.service.d

cat <<EOF | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=cpu cpuset io memory pids
EOF

sudo systemctl daemon-reload

success "\n\n\n Installation phase1 complate! Please reboot your server and run this script again!\n\n"

touch phase1.complate
exit 0
}


function phase2() {

stage "Installing containerd in rootless mode with nerdctl"	

containerd-rootless-setuptool.sh install

sudo systemctl enable --now containerd

stage "Configuring containerd"

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

sudo sed -i "/SystemdCgroup/c\SystemdCgroup = true" /etc/containerd/config.toml
sudo systemctl restart containerd

# Setup crictl conf file for prevent describe runtime endpoint on every command
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

###### Kubernetes Components Installation ######

stage "Preparing system for k8s installation"

# Get the google's pub key
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

# Add k8s apt repo
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

stage "Install and set hold k8s components"

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

rm -rf phase1.complate
rm -rf nerdctl-full-*.tar.gz

if [[ $SHELL == "/bin/bash" ]]; then
	echo "alias docker=\"sudo nerdctl --namespace k8s.io\"" >> ~/.bashrc
	info "Docker alias added for nerdctl. Please logout and re-login for alias changes effect."
elif [[ $SHELL == "/bin/zsh" ]]; then
	echo "alias docker=\"sudo nerdctl --namespace k8s.io\"" >> ~/.zshrc
	info "Docker alias added for nerdctl. Please logout and re-login for alias changes effect."
fi

success "\n\n\n Installation complate! You can now init your cluster.\n\n"
}

if [ "$EUID" -eq 0 ]
  then echo "Please run this script as a regular user!"
  exit
fi

if test -f "phase1.complate"; then
    phase2
else
    phase1    
fi