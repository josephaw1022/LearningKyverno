#!/bin/bash

set -e  # Exit on error

# Read input parameters
METALLB_CONFIG_FILE=${1:-"./manifests/metallb-config.yaml"}
CLUSTER_NAME=${2:-"kyverno-spike"}
DOMAIN=${3:-"kyverno-spike.test"}
SSL_DIR="$HOME/.ssl/root-ca"


# Get the sudo password prompt out of the way
sudo echo "Thanks!"


# Create a folder to store certificate files if it doesn't exist
if [ ! -d "$SSL_DIR" ]; then
  echo "Creating folder to store certificate files..."
  mkdir -p "$SSL_DIR"
else
  echo "Certificate folder already exists. Skipping creation."
fi

# Generate an RSA key if it doesn't exist
if [ ! -f "$SSL_DIR/root-ca-key.pem" ]; then
  echo "Generating RSA key for root CA..."
  openssl genrsa -out "$SSL_DIR/root-ca-key.pem" 2048
else
  echo "RSA key for root CA already exists. Skipping generation."
fi

# Generate a root certificate if it doesn't exist
if [ ! -f "$SSL_DIR/root-ca.pem" ]; then
  echo "Generating root CA certificate..."
  openssl req -x509 -new -nodes -key "$SSL_DIR/root-ca-key.pem" \
    -days 3650 -sha256 -out "$SSL_DIR/root-ca.pem" -subj "/CN=new-kube"
else
  echo "Root CA certificate already exists. Skipping generation."
fi

# Add SSL certificate to the trusted certificates directory on Fedora
echo "Adding root CA to the trusted certificates directory..."
sudo cp "$SSL_DIR/root-ca.pem" /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract
echo "Root CA added to trusted certificates."

# Ensure kind network exists
docker network create kind || true

# Create the Kind cluster
kind create cluster --name="${CLUSTER_NAME}" --config=./kind-config.yaml

# Extract Kind network CIDR
KIND_NET_CIDR=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')
KIND_NET_BASE=$(echo "${KIND_NET_CIDR}" | awk -F'.' '{print $1"."$2"."$3}')
METALLB_IP_START="${KIND_NET_BASE}.200"
METALLB_IP_END="${KIND_NET_BASE}.254"
METALLB_IP_RANGE="${METALLB_IP_START}-${METALLB_IP_END}"

# Ensure manifests directory exists
mkdir -p "$(dirname "$METALLB_CONFIG_FILE")"

# Create or overwrite MetalLB configuration file
cat > "$METALLB_CONFIG_FILE" <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  namespace: metallb-system
  name: default-address-pool
spec:
  addresses:
  - ${METALLB_IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  namespace: metallb-system
  name: default
EOF

echo "MetalLB configuration written to $METALLB_CONFIG_FILE"


# Create istio gateway manifest file 
cat > ./manifests/istio-gateway.yaml <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: istio-gateway
  namespace: istio-ingress
spec:
  selector:
    istio: ingress
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*"
      tls:
        httpsRedirect: true
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "*"
      tls:
        mode: SIMPLE
        credentialName: istio-ingressgateway-certs
EOF

# Add Gateway API
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
{ kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.2.0" | kubectl apply -f -; }

# Install Helm Charts dependencies using Helmfile
helmfile init > /dev/null

# Create the istio-ingress namespace and label it for Istio
kubectl create namespace istio-ingress
kubectl label namespace istio-ingress istio-injection=enabled


# Create the secret for our cluster issuer
kubectl create secret tls istio-ingressgateway-certs --key "$SSL_DIR/root-ca-key.pem" --cert "$SSL_DIR/root-ca.pem" -n istio-ingress

# Apply the Helmfile
helmfile apply --state-values-set metallbConfigPath="$METALLB_CONFIG_FILE"

# Apply the kyverno policies
kubectl apply -f ./manifests/kyverno-policies

# Apply the fallback site
kubectl apply -f ./manifests/fallback.yaml


# retrieve local load balancer IP address
LB_IP=$(kubectl get svc -n istio-ingress istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Create or override the dnsmasq configuration file for the custom domain
DNSMASQ_CONFIG_FILE="/etc/dnsmasq.d/${DOMAIN}.conf"

echo "Configuring dnsmasq for ${DOMAIN}..."
echo "address=/${DOMAIN}/${LB_IP}" | sudo tee "${DNSMASQ_CONFIG_FILE}" > /dev/null

# Restart dnsmasq to apply changes
echo "Restarting dnsmasq..."
sudo systemctl restart dnsmasq