#!/bin/bash
set -e

echo "=== Starting Cert-Manager & IONOS Infrastructure Setup on $(kubectx -c) ==="

# --- 0. PARSE GLOBAL VALUES (Ultra-Clean Version) ---
if [ ! -f cluster-values.yaml ]; then
    echo "❌ Error: cluster-values.yaml not found."
    exit 1
fi

# We use awk and tr to ensure NO hidden characters or quotes survive
IONOS_PUBLIC=$(awk -F': ' '/ionos_public_prefix/ {print $2}' cluster-values.yaml | tr -d '"\r' | xargs)
IONOS_SECRET=$(awk -F': ' '/ionos_secret/ {print $2}' cluster-values.yaml | tr -d '"\r' | xargs)
EMAIL=$(awk -F': ' '/acme_email/ {print $2}' cluster-values.yaml | tr -d '"\r' | xargs)
ISSUER_NAME=$(awk -F': ' '/issuer_name/ {print $2}' cluster-values.yaml | tr -d '"\r' | xargs)

# DEBUG: Uncomment the next two lines if Step 11 fails again to see exactly what was parsed
echo "DEBUG: Public Key is [$IONOS_PUBLIC]"
echo "DEBUG: Secret Key is [$IONOS_SECRET]"

# 1. Add Helm Repositories
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update

# 2. Namespace Setup
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

# 3. Install Core Cert-Manager
echo "Installing Core Cert-Manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.13.3 \
  --set installCRDs=true \
  --wait

# 4. Generate Webhook TLS Secret
echo "Generating Webhook TLS certificates..."
cat <<EOF > webhook-openssl.conf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = cert-manager-webhook-ionos
DNS.2 = cert-manager-webhook-ionos.cert-manager
DNS.3 = cert-manager-webhook-ionos.cert-manager.svc
EOF

openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj "/CN=cert-manager-webhook-ionos.cert-manager.svc" \
  -extensions v3_req -config webhook-openssl.conf

kubectl create secret tls cert-manager-webhook-ionos-webhook-tls \
  -n cert-manager --cert=cert.pem --key=key.pem --dry-run=client -o yaml | kubectl apply -f -

# 5. IONOS Credentials
kubectl create secret generic ionos-credentials \
  -n cert-manager \
  --from-literal=IONOS_PUBLIC_PREFIX="$IONOS_PUBLIC" \
  --from-literal=IONOS_SECRET="$IONOS_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

# 6. RBAC fixes
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cert-manager-webhook-ionos
  namespace: cert-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cert-manager-webhook-ionos:auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: cert-manager-webhook-ionos
  namespace: cert-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cert-manager-webhook-ionos:webhook-authentication-reader
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- kind: ServiceAccount
  name: cert-manager-webhook-ionos
  namespace: cert-manager
EOF

# 7. Deploy IONOS Webhook
echo "Deploying custom IONOS Webhook..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cert-manager-webhook-ionos
  namespace: cert-manager
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cert-manager-webhook-ionos
  template:
    metadata:
      labels:
        app: cert-manager-webhook-ionos
    spec:
      serviceAccountName: cert-manager-webhook-ionos
      # NOTE: hostNetwork can cause scheduling issues on some clusters. 
      # If the pod won't start, try commenting this next line out.
      hostNetwork: true 
      containers:
      - name: webhook
        image: paulmcc50/myrepo:1.2.2-custom
        imagePullPolicy: Always
        env:
        - name: GROUP_NAME
          value: "acme.fabmade.de"
        args:
        - --secure-port=443
        - --tls-cert-file=/tls/tls.crt
        - --tls-private-key-file=/tls/tls.key
        ports:
        - containerPort: 443
        volumeMounts:
        - name: certs
          mountPath: /tls
          readOnly: true
      volumes:
      - name: certs
        secret:
          secretName: cert-manager-webhook-ionos-webhook-tls
---
apiVersion: v1
kind: Service
metadata:
  name: cert-manager-webhook-ionos
  namespace: cert-manager
spec:
  type: ClusterIP
  ports:
  - port: 443
    targetPort: 443
    protocol: TCP
    name: https
  selector:
    app: cert-manager-webhook-ionos
EOF

# 8. Register APIService
echo "Registering APIService..."
cat <<EOF | kubectl apply -f -
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  name: v1alpha1.acme.fabmade.de
spec:
  group: acme.fabmade.de
  groupPriorityMinimum: 1000
  versionPriority: 15
  service:
    name: cert-manager-webhook-ionos
    namespace: cert-manager
    port: 443
  version: v1alpha1
  caBundle: $(base64 -w 0 cert.pem)
EOF

# 9. Generic ClusterIssuer
echo "Applying ClusterIssuer: $ISSUER_NAME"
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $ISSUER_NAME
spec:
  acme:
    email: $EMAIL
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
    - dns01:
        webhook:
          groupName: acme.fabmade.de
          solverName: ionos
          config:
            apiURL: https://api.hosting.ionos.com/dns/v1
            publicKeySecretRef:
              name: ionos-credentials
              key: IONOS_PUBLIC_PREFIX
            secretKeySecretRef:
              name: ionos-credentials
              key: IONOS_SECRET
EOF

# --- 10. VALIDATION ---
echo "--- Step 10: Validating Webhook Deployment ---"
# We wait for the deployment. This is more stable than waiting for the pod.
kubectl rollout status deployment/cert-manager-webhook-ionos -n cert-manager --timeout=60s

# --- 11. API TEST ---
echo "--- Step 11: Testing IONOS API Connectivity ---"
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X GET "https://api.hosting.ionos.com/dns/v1/zones" \
     -H "X-API-Key: $IONOS_PUBLIC.$IONOS_SECRET")

if [ "$API_RESPONSE" == "200" ]; then
    echo "✅ SUCCESS: IONOS API credentials are VALID."
else
    echo "❌ ERROR: IONOS API test failed with HTTP $API_RESPONSE."
    exit 1
fi

# Clean up local cert files
rm key.pem cert.pem webhook-openssl.conf

echo "=== Infrastructure Setup Complete ==="