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
    lsb-release \
    libseccomp2 \
    bash-completion

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
Delegate=cpu cpuset io memory pids rdma
EOF

sudo systemctl daemon-reload

success "\n\n\n Installation phase1 complate! Please reboot your server and run this script again!\n\n"

touch .phase1.complete
exit 0
}


function phase2() {

stage "Installing containerd"	

# Get the keyring for the docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg    

# Add the docker repo for containerd installation
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install containerd.io

stage "Getting the latest relase of nerdctl"

# Find the latest release of nerdctl full
LT_RLS="$(get_latest_release_from_github containerd/nerdctl | sed -e "s/v//g")"

# get the nerdctl full binaries
wget https://github.com/containerd/nerdctl/releases/download/v$LT_RLS/nerdctl-full-$LT_RLS-linux-amd64.tar.gz

#
# We want the use containerd binaries first which installed from docker repo
# So we need to copy nerdctl binaries under the /usr/bin if they not exists
# After that we put nerdctl dependencies under the /usr/local
# (We need to do it that way because of /usr/local/bin comes first in the $PATH)
#

# Create workdir for nerdctl files
mkdir -p resources/nerdctl

# extract the archive
sudo tar Cxzvvf resources/nerdctl nerdctl-full-$LT_RLS-linux-amd64.tar.gz --skip-old-files

# cp binaries under the /usr/bin if not exist
sudo cp -n resources/nerdctl/bin/* /usr/bin/

# remove binaries 
sudo rm -rf resources/nerdctl/bin

# copy rest of the files under the /usr/local
sudo cp -r -n resources/nerdctl/* /usr/local

# remove nerdctl's containerd.service
sudo rm -rf /usr/local/lib/systemd/system/containerd.service

# Fix buildkitd execstart path
sudo sed -i "s|ExecStart=/usr/local/bin/buildkitd|ExecStart=/usr/bin/buildkitd|g" /usr/local/lib/systemd/system/buildkit.service

# Reload daemon
sudo systemctl daemon-reload

# Enable and start buildkit service
sudo systemctl enable buildkit.service
sudo systemctl start buildkit.service

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

sudo mkdir -p /etc/systemd/system/kubelet.service.d

# Create Systemd Drop-In for Containerd
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/0-containerd.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF

sudo systemctl daemon-reload

rm -rf .phase1.complete
rm -rf nerdctl-full-*.tar.gz
rm -rf cri-containerd-cni-*.tar.gz

if [[ $SHELL == "/bin/bash" ]]; then
	echo "alias docker=\"sudo nerdctl --namespace k8s.io\"" >> ~/.bashrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
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

if test -f ".phase1.complete"; then
    phase2
else
    phase1    
fi