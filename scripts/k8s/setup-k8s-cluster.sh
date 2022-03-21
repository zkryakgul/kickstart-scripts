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
   echo "Bootup a kubernetes cluster with minimal dependencies."
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
  kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

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

  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
  
  info "Enter the start-end ip addresses for default metallb address pool:"
  read -p 'Start: ' startAddr
  read -p 'End: ' endAddr

cat <<EOF | sudo tee resources/metallb/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - $startAddr-$endAddr
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

  wget -O resources/ingress-nginx/deploy.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/baremetal/deploy.yaml
    sed -i "s/type: NodePort/type: LoadBalancer/g" resources/ingress-nginx/deploy.yaml
    sed -i "/election-id=ingress-controller-leader/a\ \ \ \ \ \ \ \ \ \ \ \ - --publish-service=\$(POD_NAMESPACE)/ingress-nginx-controller" resources/ingress-nginx/deploy.yaml
    kubectl apply -f resources/ingress-nginx/deploy.yaml

    echo -ne "\n\n"
    info "Ingress Nginx installation completed. Check the ingress-nginx status with the following command and if its up and running then continue to next step."
    info "$ kubectl get all -n ingress-nginx"
    info "Next step is setup kubernetes-dashboard with: ./setup-k8s-cluster.sh -d"
    echo -ne "\n\n"
}

function setup_kubernetes_dashboard() {

  stage "Installing Kubernetes dashboard"

  LT_RLS=$(get_latest_release_from_github kubernetes/dashboard)
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/$LT_RLS/aio/deploy/recommended.yaml

    read -p 'Enter the kubernetes dashboard FQDN for the ingress definition(ex: dashboard.k8s.local): ' dashboard_fqdn

cat <<EOF | sudo tee resources/kubernetes-dashboard/ingress.yaml
kind: Ingress
apiVersion: networking.k8s.io/v1
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
spec:
  tls:
    - hosts:
        - $dashboard_fqdn
      secretName: kubernetes-dashboard
  rules:
    - host: $dashboard_fqdn
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kubernetes-dashboard
                port:
                  number: 443
EOF

    kubectl apply -f resources/kubernetes-dashboard/ingress.yaml

    echo -ne "\n\n"
    info "kubernetes-dashboard installation complete."
    info "To create admin token follow the instructions in: https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md"
    info "Congratulations, you have installed all components for inital cluster!"
    echo -ne "\n\n"
}

if [ "$EUID" -eq 0 ]
  then echo "Please run this script as a regular user!"
  exit
fi

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
