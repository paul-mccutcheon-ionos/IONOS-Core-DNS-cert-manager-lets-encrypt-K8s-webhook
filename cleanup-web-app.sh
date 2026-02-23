#!/bin/bash

# --- 0. PARSE SITE VALUES ---
if [ ! -f site-values.yaml ]; then
    echo "❌ Error: site-values.yaml not found."
    exit 1
fi

# Extracting values and cleaning quotes/spaces/hidden characters
APP_NAMESPACE=$(grep "app_namespace" site-values.yaml | cut -d':' -f2- | tr -d '"\r ' | xargs)
CERT_NAME=$(grep "cert_name" site-values.yaml | cut -d':' -f2- | tr -d '"\r ' | xargs)
INGRESS_NAME=$(grep "ingress_name" site-values.yaml | cut -d':' -f2- | tr -d '"\r ' | xargs)
DEPLOYMENT_NAME=$(grep "deployment_name" site-values.yaml | cut -d':' -f2- | tr -d '"\r ' | xargs)

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
