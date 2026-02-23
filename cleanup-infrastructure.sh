#!/bin/bash

# --- 0. PARSE CLUSTER VALUES ---
if [ ! -f cluster-values.yaml ]; then
    echo "⚠️ Warning: cluster-values.yaml not found. Using defaults."
    ISSUER_NAME="ionos-letsencrypt-issuer"
else
    ISSUER_NAME=$(grep "issuer_name" cluster-values.yaml | cut -d':' -f2- | tr -d '"\r ' | xargs)
fi

echo "========================================================"
echo "  CLEANUP: Removing Infrastructure from $(kubectx -c)"
echo "  Target Issuer: $ISSUER_NAME"
echo "========================================================"

# --- 1. Removing APIService ---
# This is usually the same regardless of naming
echo "--- Removing APIService ---"
kubectl delete apiservice v1alpha1.acme.fabmade.de --ignore-not-found

# --- 2. Removing ClusterIssuer ---
# This now uses the name from your YAML
echo "--- Removing ClusterIssuer: $ISSUER_NAME ---"
kubectl delete clusterissuer "$ISSUER_NAME" --ignore-not-found

# --- 3. Removing Global RBAC ---
echo "--- Removing Global RBAC ---"
kubectl delete clusterrolebinding cert-manager-webhook-ionos:auth-delegator --ignore-not-found

# --- 4. Removing cert-manager Namespace ---
echo "--- Removing cert-manager Namespace ---"
kubectl delete namespace cert-manager --wait=true --ignore-not-found

echo "========================================================"
echo "✅ Infrastructure Cleanup Complete."
echo "========================================================"
