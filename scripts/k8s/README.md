# Install latest kubernetes components on ubuntu using containerd as a CRI tool.

## Usage:

- If you just want to install kubernetes with the basic containerd as cri run the following command:

```
./install-k8s-with-containerd.sh
```

- If you want to install kubernetes with the containerd and nerdctl (Docker-compatible CLI for containerd) run the following command:
  - Further information about nerdctl: https://github.com/containerd/nerdctl

```
./install-k8s-with-containerd-and-nerdctl.sh
# After the phase-1 complete reboot your server and run script again
```

## Init kubeadm for test purposes:

- Disable swap

```
sudo swapoff -a
```

- Remove the swap image from fstab
```
sudo vim /etc/fstab
```

- Init cluster 
```
sudo kubeadm init
```

- Setup for kubectl
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

- Untaint the master node for allow schedule in this node
```
kubectl taint node $(hostname) node-role.kubernetes.io/master:NoSchedule-
```

## Setup the minimal dependencies and useful tools for cluster.

- Run the `setup-k8s-cluster.sh` with the needed parameters. To see the parameters:
```
./setup-k8s-cluster.sh -h
```

### What's included?
`setup-k8s-cluster.sh` script has the installation candidates for fallowing tools:
- **-w flag:** weavenet
- **-m flag:** metallb
- **-i flag:** ingress-nginx
- **-d flag:** kubernetes-dashboard

> :warning: **Note**: Run the command parameters one by one.!
