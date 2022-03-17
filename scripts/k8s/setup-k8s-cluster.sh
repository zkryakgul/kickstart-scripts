#!/bin/bash

set -e 
set -o pipefail

LIBRARY_PATH="../../lib/"

# source all necessary files
for f in $LIBRARY_PATH*; do
 . $f
done

function setup_weavenet() {
	stage "Installing weavenet"
	kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

	info "Weavenet installation completed."
}

function setup_metallb() {
	stage "Prepare k8s for metallb"

	kubectl get configmap kube-proxy -n kube-system -o yaml | \
	sed -e "s/strictARP: false/strictARP: true/" | \
	kubectl diff -f - -n kube-system

	warn "Please inspect the changes of kube-proxy above. Metallb needs to be strictARP option is set to true."

	read -p "Is the configuration ok? " -n 1 -r
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

	info "Metallb installation completed." 

}

function setup_ingress_nginx() {

    stage "Installing Ingress Nginx"
    info "Ingress nginx service will be installed on LoadBalancer mode. So it creates an endpoint which using an ip from metallb address pool."

	wget -O resources/ingress-nginx/deploy.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.1/deploy/static/provider/baremetal/deploy.yaml
    sed -i "s/type: ClusterIP/type: LoadBalancer/g" resources/ingress-nginx/deploy.yaml
    sed -i "/election-id=ingress-controller-leader/a\ \ \ \ \ \ \ \ \ \ \ \ - --publish-service=\$(POD_NAMESPACE)/ingress-nginx-controller" resources/ingress-nginx/deploy.yaml
    kubectl apply -f resources/ingress-nginx/deploy.yaml

    info "Ingress Nginx installation completed." 
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
}

if [ "$EUID" -eq 0 ]
  then echo "Please run this script as a regular user!"
  exit
fi

setup_weavenet
setup_metallb
setup_ingress_nginx
setup_kubernetes_dashboard