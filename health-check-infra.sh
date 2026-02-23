#!/bin/bash

# Colors for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Cert-Manager IONOS Webhook Health Check ===${NC}\n"

# 1. Check Pod Status
echo "1. Checking Webhook Pod Status..."
POD_STATUS=$(kubectl get pods -n cert-manager -l app=cert-manager-webhook-ionos -o jsonpath='{.items[0].status.phase}')
if [ "$POD_STATUS" == "Running" ]; then
    echo -e "   [${GREEN}OK${NC}] Webhook Pod is Running."
else
    echo -e "   [${RED}FAIL${NC}] Webhook Pod is $POD_STATUS"
fi

# 2. Check Network Mode (HostNetwork)
echo "2. Checking Network Configuration..."
HOST_NET=$(kubectl get deployment -n cert-manager cert-manager-webhook-ionos -o jsonpath='{.spec.template.spec.hostNetwork}')
if [ "$HOST_NET" == "true" ]; then
    echo -e "   [${GREEN}OK${NC}] hostNetwork is enabled (Bypassing CNI/Firewall issues)."
else
    echo -e "   [${RED}WARN${NC}] hostNetwork is NOT enabled. This often causes 503 errors on managed clusters."
fi

# 3. Check API Service Availability
echo "3. Checking APIService Discovery..."
API_STATUS=$(kubectl get apiservice v1alpha1.acme.fabmade.de -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
if [ "$API_STATUS" == "True" ]; then
    echo -e "   [${GREEN}OK${NC}] APIService v1alpha1.acme.fabmade.de is Available."
else
    echo -e "   [${RED}FAIL${NC}] APIService is NOT available. Check 'kubectl describe apiservice v1alpha1.acme.fabmade.de'"
fi

# Optimized Step 4 for your health-check.sh
echo "4. Testing Internal Service Connectivity (TLS Handshake)..."
# We capture ONLY the status code by using a variable inside the pod
K8S_TEST=$(kubectl run debug-health-check -n cert-manager --image=curlimages/curl -q --rm -it --restart=Never -- \
  curl -s -k -o /dev/null -w "%{http_code}" https://cert-manager-webhook-ionos.cert-manager.svc/healthz)

if [[ "$K8S_TEST" == *"200"* ]]; then
    echo -e "   [${GREEN}OK${NC}] Internal TLS Handshake succeeded (HTTP 200)."
else
    echo -e "   [${RED}FAIL${NC}] Internal Handshake failed. Received: $K8S_TEST"
fi
# 5. Check IONOS Credentials Secret
echo "5. Checking IONOS Credentials..."
if kubectl get secret ionos-credentials -n cert-manager &> /dev/null; then
    echo -e "   [${GREEN}OK${NC}] Secret 'ionos-credentials' exists in cert-manager namespace."
else
    echo -e "   [${RED}FAIL${NC}] Secret 'ionos-credentials' is MISSING in cert-manager namespace."
fi

# 6. Check for Recent 503 Errors in Controller Logs
echo "6. Scanning Cert-Manager logs for 503 errors..."
ERRORS=$(kubectl logs -n cert-manager -l app=cert-manager --tail=100 | grep -c "unable to handle the request")
if [ "$ERRORS" -eq 0 ]; then
    echo -e "   [${GREEN}OK${NC}] No recent 503 errors found in cert-manager controller."
else
    echo -e "   [${RED}WARN${NC}] Found $ERRORS instances of 'unable to handle request' in recent logs."
fi


# 7. Check All Certificates Status
echo "7. Auditing Certificates..."
CERT_SUMMARY=$(kubectl get certificates -A --no-headers)
FAILED_CERTS=$(echo "$CERT_SUMMARY" | grep -v "True" | wc -l)

if [ "$FAILED_CERTS" -eq 0 ]; then
    echo -e "   [${GREEN}OK${NC}] All Certificates are READY."
else
    echo -e "   [${RED}WARN${NC}] Found $FAILED_CERTS certificate(s) that are NOT READY."
    echo "$CERT_SUMMARY" | grep -v "True" | awk '{print "        -> Namespace: " $1 " Name: " $2}'
fi

echo -e "\n${GREEN}=== Health Check Complete ===${NC}"
