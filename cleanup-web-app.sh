#!/bin/bash

# Configuration - matches your deploy script
APP_NAMESPACE="vintage-stereo"
CERT_NAME="vintagestereo-tls-secret-www3"

echo "========================================================"
echo "  CLEANUP: Removing Web App from $(kubectx -c)"
echo "========================================================"

# --- 1. CERT-MANAGER RESOURCES ---
# We delete the Certificate specifically to ensure the Order/Challenge are wiped
echo "--- Removing Certificates and Requests ---"
kubectl delete certificate $CERT_NAME -n $APP_NAMESPACE --ignore-not-found
kubectl delete certificaterequest --all -n $APP_NAMESPACE --ignore-not-found

# --- 2. INGRESS ---
echo "--- Removing Ingress ---"
kubectl delete ingress site-ingress -n $APP_NAMESPACE --ignore-not-found

# --- 3. APP SERVICES & DEPLOYMENTS ---
echo "--- Removing App Resources ---"
kubectl delete deployment vintage-stereo-deployment -n $APP_NAMESPACE --ignore-not-found
kubectl delete service vintage-stereo-service -n $APP_NAMESPACE --ignore-not-found

# --- 4. SECRETS ---
# This ensures we don't have stale TLS data or old registry keys
echo "--- Removing Secrets ---"
kubectl delete secret $CERT_NAME -n $APP_NAMESPACE --ignore-not-found
kubectl delete secret regcred -n $APP_NAMESPACE --ignore-not-found

# --- 5. NAMESPACE ---
echo "--- Removing Namespace: $APP_NAMESPACE ---"
kubectl delete namespace $APP_NAMESPACE --wait=true --ignore-not-found

echo "========================================================"
echo "✅ Web App Cleanup Complete."
echo "You can now safely run ./deploy-web-app.sh"
echo "========================================================"