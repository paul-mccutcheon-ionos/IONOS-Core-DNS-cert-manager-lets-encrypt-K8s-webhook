#!/bin/bash

# --- 1. SURGICAL PARSING ---
if [ ! -f site-values.yaml ]; then
    echo "❌ Error: site-values.yaml not found."
    exit 1
fi

NS=$(sed -n 's/^[[:space:]]*namespace:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml)
DOMAIN=$(sed -n 's/^[[:space:]]*domain:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml)
TLS_SECRET=$(sed -n 's/^[[:space:]]*tls_secret_name:[[:space:]]*"*\([^"]*\)"*/\1/p' site-values.yaml)

echo "========================================================"
echo "  HEALTH CHECK: $DOMAIN"
echo "  Cluster:      $(kubectx -c)"
echo "  Namespace:    $NS"
echo "========================================================"

# --- 2. KUBERNETES POD STATUS ---
echo "--- Pod Status ---"
kubectl get pods -n "$NS" -l app=nginx-web --no-headers | awk '{print $1 " is " $3}'
echo ""

# --- 3. DYNAMIC CERTIFICATE LOOKUP ---
echo "--- Cert-Manager Status ---"
# We look for the certificate that owns our specific secret name
CERT_NAME=$(kubectl get cert -n "$NS" -o jsonpath="{.items[?(@.spec.secretName=='$TLS_SECRET')].metadata.name}")

if [ -z "$CERT_NAME" ]; then
    echo "❌ No Certificate found managing secret: $TLS_SECRET"
else
    READY_STATUS=$(kubectl get cert "$CERT_NAME" -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$READY_STATUS" == "True" ]; then
        echo "✅ Certificate '$CERT_NAME' is VALID and READY."
    else
        echo "⚠️  Certificate '$CERT_NAME' is NOT READY (Status: $READY_STATUS)."
        echo "Last Event:"
        kubectl describe cert "$CERT_NAME" -n "$NS" | grep -A 3 "Events:" | tail -n 2
    fi
fi
echo ""

# --- 4. TLS SECRET & EXPIRY ---
echo "--- TLS Secret Details ---"
if kubectl get secret "$TLS_SECRET" -n "$NS" >/dev/null 2>&1; then
    CERT_DATA=$(kubectl get secret "$TLS_SECRET" -n "$NS" -o jsonpath='{.data.tls\.crt}' | base64 -d)
    ISSUER=$(echo "$CERT_DATA" | openssl x509 -noout -issuer)
    DATES=$(echo "$CERT_DATA" | openssl x509 -noout -dates)
    
    echo "Secret Found: $TLS_SECRET"
    echo "Issuer:       ${ISSUER#issuer=}"
    echo "$DATES"
else
    echo "❌ TLS Secret '$TLS_SECRET' not found."
fi
echo ""

# --- 5. NETWORK & ENDPOINT CHECK ---
echo "--- Connectivity Check ---"
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

# Verify if we can reach the domain over HTTPS
RESPONSE=$(curl -s -I --connect-timeout 5 "https://$DOMAIN" | grep HTTP/ || echo "Failed to connect")

echo "LoadBalancer:  $LB_IP"
echo "Target URL:    https://$DOMAIN"
echo "Response:      $RESPONSE"

if [[ "$RESPONSE" == *"200"* ]]; then
    echo "✅ SUCCESS: Site is live over HTTPS."
else
    echo "⚠️  Handshake failed. Use this for debugging:"
    echo "   curl -vI --resolve $DOMAIN:443:$LB_IP https://$DOMAIN"
fi
echo "========================================================"
