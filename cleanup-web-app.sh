#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_PATH="$SCRIPT_DIR/site-values.yaml"

# --- 0. PARSE SITE VALUES (Corrected for site: prefix) ---
if [ ! -f "$YAML_PATH" ]; then
    echo "❌ Error: site-values.yaml not found at $YAML_PATH"
    exit 1
fi

# Updated to match your actual site-values.yaml keys
APP_NAMESPACE=$(grep "namespace:" "$YAML_PATH" | cut -d':' -f2- | tr -d '"\r ' | xargs)
CERT_NAME=$(grep "tls_secret_name:" "$YAML_PATH" | cut -d':' -f2- | tr -d '"\r ' | xargs)
# Since your YAML doesn't have these specifically, we'll set defaults or use the domain
INGRESS_NAME="site-ingress" 
DEPLOYMENT_NAME="nginx-web"

# CRITICAL SAFETY CHECK
if [ -z "$APP_NAMESPACE" ] || [ -z "$CERT_NAME" ]; then
    echo "❌ Error: Could not parse 'namespace' or 'tls_secret_name' from site-values.yaml"
    exit 1
fi

echo "========================================================"
echo "  CLEANUP: Removing App [$DEPLOYMENT_NAME] from $(kubectx -c)"
echo "  Target Namespace: $APP_NAMESPACE"
echo "========================================================"

# --- 1. CERT-MANAGER RESOURCES ---
echo "--- Removing Certificates and Requests ---"
kubectl delete certificate "$CERT_NAME" -n "$APP_NAMESPACE" --ignore-not-found
kubectl delete certificaterequest --all -n "$APP_NAMESPACE" --ignore-not-found

# --- 2. INGRESS ---
echo "--- Removing Ingress ---"
kubectl delete ingress "$INGRESS_NAME" -n "$APP_NAMESPACE" --ignore-not-found

# --- 3. APP SERVICES & DEPLOYMENTS ---
echo "--- Removing App Resources ---"
# We target the deployment and service by name or by label if preferred
kubectl delete deployment "$DEPLOYMENT_NAME" -n "$APP_NAMESPACE" --ignore-not-found
kubectl delete service "$DEPLOYMENT_NAME-service" -n "$APP_NAMESPACE" --ignore-not-found

# --- 4. SECRETS ---
echo "--- Removing Secrets ---"
kubectl delete secret "$CERT_NAME" -n "$APP_NAMESPACE" --ignore-not-found
kubectl delete secret regcred -n "$APP_NAMESPACE" --ignore-not-found

# --- 5. NAMESPACE ---
echo "--- Removing Namespace: $APP_NAMESPACE ---"
echo "(This will delete all remaining pods and local resources...)"
kubectl delete namespace "$APP_NAMESPACE" --wait=true --ignore-not-found

echo "========================================================"
echo "✅ Web App Cleanup Complete for $APP_NAMESPACE"
echo "========================================================"
