#!/bin/bash

# Define the namespace name
NAMESPACE="test-lb-functionality"

# Create the namespace
kubectl create namespace $NAMESPACE

# Create the Nginx deployment in the namespace
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
EOF

# Create the service to expose the Nginx deployment
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: $NAMESPACE
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: LoadBalancer
EOF


# Get the external IP address of the Nginx service
EXTERNAL_IP=$(kubectl get svc nginx-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test the Nginx service
OUTPUT=$(curl -s $EXTERNAL_IP)

# Check if the output contains the "Welcome to nginx!" message
if [[ $OUTPUT == *"Welcome to nginx!"* ]]; then
  echo "Nginx service is working correctly"
else
  echo "Nginx service is not working correctly"
fi
