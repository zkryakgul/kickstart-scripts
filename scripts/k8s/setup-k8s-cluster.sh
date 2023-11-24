#!/bin/bash

set -e 
set -o pipefail

LIBRARY_PATH="../../lib/"

# source all necessary files
for f in $LIBRARY_PATH*; do
 . $f
done

function Help()
{
   # Display Help
   echo "Bootup a kubernetes cluster with minimal dependencies. Requires access to cluster with kubectl"
   echo
   echo "Syntax: ./setup-k8s-cluster [-w|-m|-i|-d|-h]"
   echo "options:"
   echo "-w     installs the weavenet components to the cluster."
   echo "-m     installs the metallb components to the cluster."
   echo "-i     installs the ingress-nginx components to the cluster"
   echo "-d     installs the kubernetes-dashboard components to the cluster."
   echo "-h     prints this help message."
   echo
}

function setup_weavenet() {
  stage "Installing weavenet"
  kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml

  echo -ne "\n\n"
  info "Weavenet installation completed. Check the weavenet status with the following command and if its up and running then continue to next step."
  info "$ kubectl get all -n kube-system"
  info "Next step is setup metallb with: ./setup-k8s-cluster.sh -m"
  echo -ne "\n\n"
}

function setup_metallb() {
  stage "Prepare k8s for metallb"

  set +e 
  set +o pipefail

  kubectl get configmap kube-proxy -n kube-system -o yaml | \
  sed -e "s/strictARP: false/strictARP: true/" | \
  kubectl diff -f - -n kube-system

  set -e 
  set -o pipefail

  warn "Please inspect the changes of kube-proxy above. Metallb needs to be strictARP option is set to true."

  read -p "Is the configuration ok? (y/n)" -n 1 -r
  echo    # (optional) move to a new line
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
      kubectl get configmap kube-proxy -n kube-system -o yaml | \
    sed -e "s/strictARP: false/strictARP: true/" | \
    kubectl apply -f - -n kube-system
  fi

  stage "Installing metallb"

  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

  
  info "Enter the start-end ip addresses for default metallb address pool:"
  read -p 'Start: ' startAddr
  read -p 'End: ' endAddr

cat <<EOF | sudo tee resources/metallb/config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - $startAddr-$endAddr 
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
EOF

  kubectl apply -f resources/metallb/config.yaml -n metallb-system

  echo -ne "\n\n"
  info "Metallb installation completed. Check the metallb status with the following command and if its up and running then continue to next step."
  info "$ kubectl get all -n metallb-system"
  info "Next step is setup ingress-nginx with: ./setup-k8s-cluster.sh -i"

  warn "If Metallb speaker status become CreateContainerConfigError due to memberlist error run the command below:"
  info "kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey=\"\$(openssl rand -base64 128)\""
  echo -ne "\n\n"

}

function setup_ingress_nginx() {

    stage "Installing Ingress Nginx"
    info "Ingress nginx service will be installed on LoadBalancer mode. So it creates an endpoint which using an ip from metallb address pool."

    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

    echo -ne "\n\n"
    info "Ingress Nginx installation completed. Check the ingress-nginx status with the following command and if its up and running then continue to next step."
    info "$ kubectl get all -n ingress-nginx"
    info "Next step is setup kubernetes-dashboard with: ./setup-k8s-cluster.sh -d"
    echo -ne "\n\n"
}

function setup_helm() {
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
}

function setup_kubernetes_dashboard() {
    stage "Installing Kubernetes dashboard"
    
    setup_helm

    # 
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

    sleep 90

    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    read -p 'Enter the kubernetes dashboard FQDN for the ingress definition(ex: dashboard.k8s.local): ' dashboard_fqdn

    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
                 --create-namespace --namespace kubernetes-dashboard \
                 --set nginx.enabled=false \
                 --set cert-manager.enabled=false \
                 --set app.ingress.hosts="{$dashboard_fqdn}" \
                 --set app.ingress.ingressClassName="nginx" \
                 --version 7.0.0-alpha1

    echo -ne "\n\n"
    info "kubernetes-dashboard installation complete."
    info "To create admin token follow the instructions in: https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md"
    info "Congratulations, you have installed all components for inital cluster!"
    echo -ne "\n\n"
}

# Get the options
while getopts ":hZ:wZ:mZ:iZ:dZ:" option; do
   case $option in
      h) # display Help
         Help
         exit;;
      w)
         setup_weavenet
         exit;;
      m)
         setup_metallb
         exit;;
      i)
         setup_ingress_nginx
         exit;;
      d)
         setup_kubernetes_dashboard
         exit;;
      *) # incorrect option
         echo "Error: Invalid option"
         exit;;
   esac
done

Help