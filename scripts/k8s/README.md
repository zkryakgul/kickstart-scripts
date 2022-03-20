# Install latest kubernetes components on ubuntu using containerd as a CRI tool.

## Usage:
```
./install-k8s-with-containerd.sh
```

or run the command below for install with nerdctl

```
./install-k8s-with-containerd-and-nerdctl.sh
```

- After the phase 1 complate reboot your server and run script again

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