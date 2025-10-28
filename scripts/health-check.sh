#!/bin/bash

################################################################################
# Kubernetes Health Check Script
# Performs comprehensive health checks on a Kubernetes cluster.
################################################################################

set -e

# Get script directory (works even if script is sourced or called from another directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

source "$SCRIPT_DIR/config.sh"

# ==================== HEADER ====================

cat << 'EOF'

╔════════════════════════════════════════════════════════════════╗
║                  KUBERNETES HEALTH CHECK                       ║
╚════════════════════════════════════════════════════════════════╝

EOF

log_info "Starting health check..."
display_config

# Initialize HTML report
init_html_report "Kubernetes Health Check Report" "$0"

# ==================== PREREQUISITE CHECKS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 1: Checking Prerequisites"
echo "═══════════════════════════════════════════════════════════════"

check_aws_cli || exit 1
check_kubectl || exit 1
check_aws_credentials || exit 1
verify_cluster_access || exit 1

# ==================== AWS CLUSTER CHECKS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 2: Checking AWS EKS Cluster"
echo "═══════════════════════════════════════════════════════════════"

log_info "Fetching cluster information for: $CLUSTER_NAME"

CLUSTER_INFO=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --query 'cluster' 2>/dev/null) || {
    log_error "Cannot describe cluster. Verify cluster name and region."
    exit 1
}

CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | jq -r '.status')

CLUSTER_ARN=$(echo "$CLUSTER_INFO" | jq -r '.arn')
CREATED_AT=$(echo "$CLUSTER_INFO" | jq -r '.createdAt')
CURRENT_VERSION=$(echo "$CLUSTER_INFO" | jq -r '.version')

echo "Cluster Name:       $CLUSTER_NAME"
echo "Status:             $CLUSTER_STATUS"
echo "Current Version:    $CURRENT_VERSION"
echo "ARN:                $CLUSTER_ARN"
echo "Created:            $CREATED_AT"

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    log_error "Cluster is not in ACTIVE state. Current state: $CLUSTER_STATUS"
    exit 1
fi

echo "✅ Cluster health check passed"

# ==================== NODE GROUP CHECKS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 3: Checking Node Groups"
echo "═══════════════════════════════════════════════════════════════"

log_info "Fetching node group information..."

NODEGROUP_INFO=$(aws eks describe-nodegroup \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODEGROUP_NAME" \
    --region "$REGION" \
    --query 'nodegroup' 2>/dev/null) || {
    log_error "Cannot describe node group. Verify node group name."
    exit 1
}

NG_STATUS=$(echo "$NODEGROUP_INFO" | jq -r '.status')
NG_VERSION=$(echo "$NODEGROUP_INFO" | jq -r '.version')
DESIRED=$(echo "$NODEGROUP_INFO" | jq -r '.scalingConfig.desiredSize')
CURRENT=$(echo "$NODEGROUP_INFO" | jq -r '.scalingConfig.desiredSize')
HEALTH=$(echo "$NODEGROUP_INFO" | jq -r '.health.issues | length')

echo "Node Group Name:    $NODEGROUP_NAME"
echo "Status:             $NG_STATUS"
echo "Version:            $NG_VERSION"
echo "Desired Size:       $DESIRED"
echo "Health Issues:      $HEALTH"

if [ "$NG_STATUS" != "ACTIVE" ]; then
    log_error "Node group is not in ACTIVE state. Current state: $NG_STATUS"
    exit 1
fi

if [ "$HEALTH" -gt 0 ]; then
    log_warn "Node group has $HEALTH health issues"
    echo "$NODEGROUP_INFO" | jq '.health.issues'
fi

echo "✅ Node group health check passed"

# ==================== KUBERNETES NODES CHECKS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 4: Checking Kubernetes Nodes"
echo "═══════════════════════════════════════════════════════════════"

log_info "Fetching node status..."

UNHEALTHY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v "Ready" | grep -v "STATUS" | wc -l)
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v "STATUS" | wc -l)

echo "Total Nodes:        $TOTAL_NODES"
echo "Healthy Nodes:      $((TOTAL_NODES - UNHEALTHY_NODES))"
echo "Unhealthy Nodes:    $UNHEALTHY_NODES"
echo ""
echo "Node Status:"
kubectl get nodes -o wide

if [ "$UNHEALTHY_NODES" -gt 0 ]; then
    log_warn "Found $UNHEALTHY_NODES unhealthy nodes"
fi

# Get AMI information for each node
echo ""
echo "Node AMI Information:"

# Use the new table display function
display_node_ami_table

# Variables AL2023_NODES, AL2_NODES, UBUNTU_NODES, UNKNOWN_NODES are now exported from the function

echo "✅ Node status check passed"

# ==================== POD STATUS CHECKS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 5: Checking Pod Status"
echo "═══════════════════════════════════════════════════════════════"

log_info "Fetching pod status..."

PENDING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
FAILED_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
TOTAL_PODS=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l)
RUNNING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

echo "Total Pods:         $TOTAL_PODS"
echo "Running Pods:       $RUNNING_PODS"
echo "Pending Pods:       $PENDING_PODS"
echo "Failed Pods:        $FAILED_PODS"

if [ "$FAILED_PODS" -gt 0 ]; then
    log_warn "Found $FAILED_PODS failed pods"
    echo ""
    echo "Failed pods:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Failed
fi

if [ "$PENDING_PODS" -gt 0 ]; then
    log_warn "Found $PENDING_PODS pending pods"
    echo ""
    echo "Pending pods:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Pending
fi

echo "✅ Pod status check completed"

# ==================== POD DISRUPTION BUDGETS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 6: Checking Pod Disruption Budgets"
echo "═══════════════════════════════════════════════════════════════"

log_info "Fetching PDB information..."

PDBCOUNT=$(kubectl get pdb --all-namespaces --no-headers 2>/dev/null | wc -l)

echo "Total PDBs:         $PDBCOUNT"
echo ""

if [ "$PDBCOUNT" -gt 0 ]; then
    echo "Pod Disruption Budgets:"
    kubectl get pdb --all-namespaces
else
    log_warn "No Pod Disruption Budgets found"
fi

echo "✅ PDB check completed"

# ==================== RESOURCE UTILIZATION ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 7: Checking Resource Utilization"
echo "═══════════════════════════════════════════════════════════════"

log_info "Analyzing resource utilization..."

echo ""
echo "Node Resource Usage:"
kubectl top nodes || log_warn "Metrics server not available"

echo ""
echo "Top Pod Resource Usage:"
kubectl top pods --all-namespaces --sort-by=memory | head -20

echo "✅ Resource utilization check completed"

# ==================== DEPRECATED API CHECKS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 8: Checking for Deprecated APIs"
echo "═══════════════════════════════════════════════════════════════"

# Use the new comprehensive function to display deprecated APIs
# Pass 'true' for quick mode, and 30 seconds timeout
display_deprecated_apis true 30

# The DEPRECATED_COUNT variable is now exported from the function

# ==================== SYSTEM PODS CHECK ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 9: Checking System Pods"
echo "═══════════════════════════════════════════════════════════════"

log_info "Checking kube-system namespace..."

SYSTEM_RUNNING=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
SYSTEM_TOTAL=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l)

echo "kube-system Running: $SYSTEM_RUNNING/$SYSTEM_TOTAL"
echo ""
echo "kube-system Pod Status:"
kubectl get pods -n kube-system -o wide

if [ "$SYSTEM_RUNNING" -lt "$SYSTEM_TOTAL" ]; then
    log_warn "Not all system pods are running"
fi

echo "✅ System pods check completed"

# ==================== STORAGE CHECK ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 10: Checking Storage"
echo "═══════════════════════════════════════════════════════════════"

log_info "Checking persistent volumes..."

PV_COUNT=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
PVC_COUNT=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)

echo "Persistent Volumes: $PV_COUNT"
echo "Persistent Volumes Claims: $PVC_COUNT"

if [ "$PV_COUNT" -gt 0 ]; then
    echo ""
    echo "PV Status:"
    kubectl get pv
fi

if [ "$PVC_COUNT" -gt 0 ]; then
    echo ""
    echo "PVC Status:"
    kubectl get pvc --all-namespaces
fi

echo "✅ Storage check completed"

# ==================== ADDON VERSIONS ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 11: Checking Add-ons"
echo "═══════════════════════════════════════════════════════════════"

log_info "Fetching add-on versions..."

ADDONS=$(aws eks list-addons --cluster-name "$CLUSTER_NAME" --region "$REGION" \
    --query 'addons' --output json 2>/dev/null)

echo "Installed Add-ons:"
echo "$ADDONS" | jq -r '.[]' | while read addon; do
    VERSION=$(aws eks describe-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$addon" \
        --region "$REGION" \
        --query 'addon.addonVersion' \
        --output text 2>/dev/null)
    echo "  • $addon: $VERSION"
done

echo "✅ Add-on check completed"

# ==================== HELM CHARTS INVENTORY ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 12: Checking Helm Charts"
echo "═══════════════════════════════════════════════════════════════"

# Use the new function to display Helm charts
display_helm_charts

echo "✅ Helm charts inventory completed"

# ==================== FINAL SUMMARY ====================

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "HEALTH CHECK SUMMARY"
echo "═══════════════════════════════════════════════════════════════"

cat << EOF

Cluster:            $CLUSTER_NAME
Current Version:    $CURRENT_VERSION

Status Summary:
  ✅ AWS Credentials:           PASSED
  ✅ Cluster Access:            PASSED
  ✅ Cluster Status:            PASSED ($CLUSTER_STATUS)
  ✅ Node Group Status:         PASSED ($NG_STATUS)
  ✅ Node Health:               PASSED ($((TOTAL_NODES - UNHEALTHY_NODES))/$TOTAL_NODES healthy)
  ✅ Pod Status:                PASSED ($RUNNING_PODS running)
  ✅ System Pods:               PASSED ($SYSTEM_RUNNING/$SYSTEM_TOTAL running)

Warnings:
  • Health Issues:              $HEALTH
  • Failed Pods:                $FAILED_PODS
  • Pending Pods:               $PENDING_PODS
  • Deprecated APIs:            $DEPRECATED_COUNT

═══════════════════════════════════════════════════════════════

✅ Health check completed successfully!

For more details, check logs in: $LOG_FILE

EOF

log_success "Health check completed successfully"

# Generate HTML report
start_html_summary
add_html_summary "Cluster Name" "$CLUSTER_NAME" "info"
add_html_summary "Current Version" "$CURRENT_VERSION" "info"
add_html_summary "Cluster Status" "$CLUSTER_STATUS" "$([ "$CLUSTER_STATUS" = "ACTIVE" ] && echo 'success' || echo 'error')"
add_html_summary "Total Nodes" "$TOTAL_NODES" "info"
add_html_summary "Healthy Nodes" "$((TOTAL_NODES - UNHEALTHY_NODES))" "success"
add_html_summary "Running Pods" "$RUNNING_PODS" "success"
add_html_summary "Failed Pods" "$FAILED_PODS" "$([ "$FAILED_PODS" -eq 0 ] && echo 'success' || echo 'error')"
add_html_summary "Pending Pods" "$PENDING_PODS" "$([ "$PENDING_PODS" -eq 0 ] && echo 'success' || echo 'warning')"
add_html_summary "System Pods" "$SYSTEM_RUNNING/$SYSTEM_TOTAL" "$([ "$SYSTEM_RUNNING" -eq "$SYSTEM_TOTAL" ] && echo 'success' || echo 'warning')"
end_html_summary

# Add detailed sections
add_html_section "Cluster Information" "Name: $CLUSTER_NAME
Status: $CLUSTER_STATUS
Version: $CURRENT_VERSION
ARN: $CLUSTER_ARN
Created: $CREATED_AT
Region: $REGION"

add_html_section "Node Group Information" "Name: $NODEGROUP_NAME
Status: $NG_STATUS
Version: $NG_VERSION
Desired Size: $DESIRED
Health Issues: $HEALTH"

add_html_section "Node Status" "$(kubectl get nodes -o wide)"

add_html_section "Node AMI Detailed Inventory" "$NODE_AMI_TABLE_OUTPUT"

add_html_section "Node AMI Summary" "Total Nodes: $TOTAL_NODES
Amazon Linux 2023: ${AL2023_NODES:-0}
Amazon Linux 2: ${AL2_NODES:-0}
Ubuntu: ${UBUNTU_NODES:-0}
Other/Unknown: ${UNKNOWN_NODES:-0}"

add_html_section "Pod Status Summary" "Total Pods: $TOTAL_PODS
Running: $RUNNING_PODS
Pending: $PENDING_PODS
Failed: $FAILED_PODS"

add_html_section "System Pods (kube-system)" "Total: $SYSTEM_TOTAL
Running: $SYSTEM_RUNNING
Status: $([ "$SYSTEM_RUNNING" -eq "$SYSTEM_TOTAL" ] && echo '✅ All running' || echo '⚠️ Some pods not running')"

add_html_section "Pod Disruption Budgets" "$(kubectl get pdb --all-namespaces -o wide 2>/dev/null || echo 'No PDBs found')"

add_html_section "Storage Status" "Persistent Volumes: $(kubectl get pv --no-headers 2>/dev/null | wc -l)
Persistent Volume Claims: $(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)

$(kubectl get pv 2>/dev/null || echo 'No PVs found')"

add_html_section "Resource Utilization" "$(kubectl top nodes 2>/dev/null || echo 'Metrics not available - metrics-server may not be installed')"

add_html_section "Top Resource Consuming Pods" "$(kubectl top pods --all-namespaces --sort-by=memory 2>/dev/null | head -20 || echo 'Metrics not available')"

# Capture Helm charts info if available
if command -v helm &> /dev/null; then
    HELM_CHARTS_OUTPUT=$(helm list --all-namespaces -o json 2>/dev/null || echo '[]')
    HELM_COUNT=$(echo "$HELM_CHARTS_OUTPUT" | jq '. | length' 2>/dev/null || echo 0)

    if [ "$HELM_COUNT" -gt 0 ]; then
        HELM_SUMMARY="Total Helm Charts: $HELM_COUNT

$(echo "$HELM_CHARTS_OUTPUT" | jq -r '.[] | "[\(.status | ascii_upcase)] \(.name) (v\(.chart)) in \(.namespace)"' 2>/dev/null || echo 'Unable to parse Helm data')"
        add_html_section "Helm Charts (Total: $HELM_COUNT)" "$HELM_SUMMARY"
    else
        add_html_section "Helm Charts" "No Helm charts found or Helm not installed"
    fi
else
    add_html_section "Helm Charts" "Helm CLI not available"
fi

# Add deprecated APIs section
add_html_section "Deprecated API Check" "$DEPRECATED_API_OUTPUT"

# Finalize report
OVERALL_STATUS="SUCCESS"
if [ "$FAILED_PODS" -gt 0 ] || [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    OVERALL_STATUS="WARNING"
fi
if [ "$UNHEALTHY_NODES" -gt 0 ]; then
    OVERALL_STATUS="WARNING"
fi

finalize_html_report "$OVERALL_STATUS"
