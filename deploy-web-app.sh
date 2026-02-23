#!/bin/bash
set -e

# --- 1. SURGICAL PARSING ---
# Using sed with line-start anchors to ensure we get exactly the right values
if [ ! -f site-values.yaml ]; then
    echo "❌ Error: site-values.yaml not found."
    exit 1
fi

NS=$(sed -n 's/^[[:space:]]*namespace:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml)
DOMAIN=$(sed -n 's/^[[:space:]]*domain:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml)
IP=$(sed -n 's/^[[:space:]]*loadBalancerIP:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml | tr -d ' ')
TLS_SECRET=$(sed -n 's/^[[:space:]]*tls_secret_name:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml)
ISSUER=$(sed -n 's/^[[:space:]]*issuer_name:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml)

echo "========================================================"
echo "  DEPLOYING TO CLUSTER: $(kubectx -c)"
echo "  Target Domain:        $DOMAIN"
echo "  Namespace:            $NS"
echo "========================================================"

# --- 2. PRE-FLIGHT SYSTEM CHECKS ---
echo "--- Step 1: Pre-flight System Checks ---"
if ! kubectl get clusterissuer "$ISSUER" >/dev/null 2>&1; then
    echo "❌ ERROR: ClusterIssuer '$ISSUER' not found on this cluster."
    echo "Ensure the IONOS Webhook is installed on $(kubectx -c) first."
    exit 1
fi
echo "✅ System tools found."

# --- 3. INFRASTRUCTURE SETUP ---
echo "--- Step 2: Preparing Namespace & RBAC ---"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

# Applying RBAC fixes for the IONOS solver and secret reader
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cert-manager-webhook-ionos:solver
rules:
  - apiGroups: ["acme.fabmade.de"]
    resources: ["ionos"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cert-manager-webhook-ionos:solver
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cert-manager-webhook-ionos:solver
subjects:
  - kind: ServiceAccount
    name: cert-manager
    namespace: cert-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cert-manager-webhook-ionos:secret-reader
  namespace: cert-manager
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["ionos-credentials"]
    verbs: ["get", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cert-manager-webhook-ionos:secret-reader
  namespace: cert-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: cert-manager-webhook-ionos:secret-reader
subjects:
  - kind: ServiceAccount
    name: cert-manager-webhook-ionos
    namespace: cert-manager
EOF

# --- 4. INGRESS CONTROLLER ---
echo "--- Step 3: NGINX Ingress Controller ---"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1
helm repo update >/dev/null 2>&1
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.loadBalancerIP="$IP" \
  --set controller.admissionWebhooks.enabled=false \
  --wait

# --- 5. BACKEND APPLICATION ---
echo "--- Step 4: Deploying NGINX Backend Pods ---"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-web
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-web
  template:
    metadata:
      labels:
        app: nginx-web
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: $NS
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: nginx-web
EOF

# --- 6. TLS & INGRESS ROUTING ---
# Using the Ingress Shim approach to avoid ghost certificates
echo "--- Step 5: Applying Ingress (Auto-TLS) ---"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: site-ingress
  namespace: $NS
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: $ISSUER
spec:
  tls:
  - hosts:
    - $DOMAIN
    secretName: $TLS_SECRET
  rules:
  - host: $DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
EOF

echo "========================================================"
echo "✅ Deployment Complete on $(kubectx -c)!"
echo "Check pods:        kubectl get pods -n $NS"
echo "Check certificate: kubectl get cert -n $NS"
echo "========================================================"
