#!/bin/bash
# set -e  # We don't use -e here so the script continues even if a resource is already gone

echo "========================================================"
echo "  CLEANUP: Removing Infrastructure from $(kubectx -c)"
echo "========================================================"

# --- 1. APISERVICE ---
echo "--- Removing APIService ---"
kubectl delete apiservice v1alpha1.acme.fabmade.de --ignore-not-found

# --- 2. CLUSTER-WIDE ISSUERS ---
echo "--- Removing ClusterIssuers ---"
# This deletes any clusterissuer, but we target the webhook-specific ones
kubectl delete clusterissuer ionos-issuer --ignore-not-found
kubectl delete clusterissuer ionos-webhook-issuer --ignore-not-found

# --- 3. RBAC (Global) ---
echo "--- Removing Global RBAC ---"
kubectl delete clusterrole cert-manager-webhook-ionos:solver --ignore-not-found
kubectl delete clusterrolebinding cert-manager-webhook-ionos:solver --ignore-not-found
kubectl delete clusterrolebinding cert-manager-webhook-ionos:auth-delegator --ignore-not-found

# --- 4. NAMESPACE (Local) ---
echo "--- Removing cert-manager Namespace ---"
echo "(This may take a minute as it cleans up all internal resources...)"
kubectl delete namespace cert-manager --wait=true --ignore-not-found

# --- 5. CRD CLEANUP (Optional but recommended for a 'True' reset) ---
# Note: Deleting CRDs will delete ALL cert-manager resources in ALL namespaces.
# If you want a 100% clean slate for cert-manager itself, uncomment these:
# echo "--- Removing cert-manager CRDs ---"
# kubectl delete crd certificates.cert-manager.io certificaterequests.cert-manager.io challenges.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io orders.cert-manager.io --ignore-not-found

echo "========================================================"
echo "✅ Cleanup Complete on $(kubectx -c)"
echo "You can now safely run ./setup-ionos-infrastructure.sh"
echo "========================================================"