#!/bin/bash

################################################################################
# Configuration File for Kubernetes Health Check
# Edit this file with your cluster details before running scripts
################################################################################

# ==================== CLUSTER CONFIGURATION ====================

# Cluster name - priority: 1) ENV var 2) kubeconfig current-context 3) default value
if [ -n "${EKS_CLUSTER_NAME}" ]; then
    # Use environment variable if set
    CLUSTER_NAME="${EKS_CLUSTER_NAME}"
else
    # Try to get from kubeconfig current-context
    if command -v kubectl &> /dev/null; then
        CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
        if [[ "$CURRENT_CONTEXT" == */* ]]; then
            # Extract cluster name from context (format: arn:aws:eks:region:account:cluster/cluster-name)
            EXTRACTED_CLUSTER=$(echo "$CURRENT_CONTEXT" | awk -F'/' '{print $NF}')
            if [ -n "$EXTRACTED_CLUSTER" ]; then
                CLUSTER_NAME="$EXTRACTED_CLUSTER"
            else
                CLUSTER_NAME="your-cluster-name"  # Default if extraction fails
            fi
        else
            CLUSTER_NAME="your-cluster-name"  # Default if context format is unexpected
        fi
    else
        CLUSTER_NAME="your-cluster-name"  # Default if kubectl not available
    fi
fi

# AWS Region - priority: 1) ENV var 2) extract from kubeconfig 3) default value
if [ -n "${AWS_REGION}" ]; then
    # Use environment variable if set
    REGION="${AWS_REGION}"
elif [ -n "${AWS_DEFAULT_REGION}" ]; then
    # Use AWS_DEFAULT_REGION if set
    REGION="${AWS_DEFAULT_REGION}"
else
    # Try to extract from kubeconfig if possible
    if command -v kubectl &> /dev/null && [ -n "$CURRENT_CONTEXT" ] && [[ "$CURRENT_CONTEXT" == *:* ]]; then
        EXTRACTED_REGION=$(echo "$CURRENT_CONTEXT" | grep -o 'eks:[^:]*' | cut -d':' -f2)
        if [ -n "$EXTRACTED_REGION" ]; then
            REGION="$EXTRACTED_REGION"
        else
            REGION="us-east-1"  # Default if extraction fails
        fi
    else
        REGION="us-east-1"  # Default
    fi
fi

# Current node group name - priority: 1) ENV var 2) default value
if [ -n "${EKS_NODEGROUP_NAME}" ]; then
    NODEGROUP_NAME="${EKS_NODEGROUP_NAME}"
else
    # Try to get the first nodegroup from the cluster
    if command -v aws &> /dev/null && [ "$CLUSTER_NAME" != "your-cluster-name" ]; then
        FIRST_NODEGROUP=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" \
            --query 'nodegroups[0]' --output text 2>/dev/null)
        if [ -n "$FIRST_NODEGROUP" ] && [ "$FIRST_NODEGROUP" != "None" ]; then
            NODEGROUP_NAME="$FIRST_NODEGROUP"
        else
            NODEGROUP_NAME="your-nodegroup-name"  # Default if no nodegroups found
        fi
    else
        NODEGROUP_NAME="your-nodegroup-name"  # Default
    fi
fi

# Target Kubernetes version is read from the cluster
# TARGET_VERSION="1.33"

# ==================== NODE CONFIGURATION ====================

# Desired number of nodes
DESIRED_SIZE=3

# Minimum number of nodes
MIN_SIZE=1

# Maximum number of nodes
MAX_SIZE=5

# Instance type(s) - space-separated for multiple
INSTANCE_TYPES="t3.large"

# AMI Type for new node group
# Options: AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, AL2023_x86_64, AL2023_ARM_64
AMI_TYPE="AL2_x86_64"

# ==================== HEALTH CHECK CONFIGURATION ====================

# Enable dry-run mode (shows what would happen without making changes)
DRY_RUN=false

# ==================== NODE DRAIN CONFIGURATION ====================

# Ignore DaemonSet pods during drain
IGNORE_DAEMONSETS=true

# Delete local storage during drain
DELETE_LOCAL_STORAGE=true

# Force deletion of pods without disruption budget
FORCE_DELETE=false

# ==================== NOTIFICATION CONFIGURATION ====================

# Enable notifications (requires jq and appropriate setup)
ENABLE_NOTIFICATIONS=false

# Notification webhook URL (optional, for Slack, Teams, etc.)
WEBHOOK_URL=""

# ==================== LOGGING CONFIGURATION ====================

# Enable verbose logging
VERBOSE=true

# Log directory
LOG_DIR="$(dirname "${BASH_SOURCE[0]}")/logs"

# Reports directory for HTML reports
REPORTS_DIR="$(dirname "${BASH_SOURCE[0]}")/reports"

# Create log and reports directories if they don't exist
mkdir -p "$LOG_DIR" 2>/dev/null || true
mkdir -p "$REPORTS_DIR" 2>/dev/null || true

# Log file with timestamp
LOG_FILE="$LOG_DIR/health-check-$(date +%Y%m%d-%H%M%S).log"

# ==================== VALIDATION ====================

# Function to validate configuration
validate_config() {
    local errors=0

    if [ -z "$CLUSTER_NAME" ]; then
        echo "ERROR: CLUSTER_NAME is not set"
        echo "       Set EKS_CLUSTER_NAME environment variable or configure kubectl context"
        ((errors++))
    elif [ "$CLUSTER_NAME" = "your-cluster-name" ]; then
        echo "WARNING: Using default CLUSTER_NAME. This is likely not what you want."
        echo "         Set EKS_CLUSTER_NAME environment variable or configure kubectl context"
    fi

    if [ -z "$REGION" ]; then
        echo "ERROR: REGION is not set"
        echo "       Set AWS_REGION or AWS_DEFAULT_REGION environment variable"
        ((errors++))
    fi

    if [ -z "$NODEGROUP_NAME" ]; then
        echo "ERROR: NODEGROUP_NAME is not set"
        echo "       Set EKS_NODEGROUP_NAME environment variable"
        ((errors++))
    elif [ "$NODEGROUP_NAME" = "your-nodegroup-name" ]; then
        echo "WARNING: Using default NODEGROUP_NAME. This is likely not what you want."
        echo "         Set EKS_NODEGROUP_NAME environment variable or ensure cluster name is correct"
    fi

    if [ "$DESIRED_SIZE" -lt "$MIN_SIZE" ]; then
        echo "ERROR: DESIRED_SIZE ($DESIRED_SIZE) is less than MIN_SIZE ($MIN_SIZE)"
        ((errors++))
    fi

    if [ "$MIN_SIZE" -gt "$MAX_SIZE" ]; then
        echo "ERROR: MIN_SIZE ($MIN_SIZE) is greater than MAX_SIZE ($MAX_SIZE)"
        ((errors++))
    fi

    # Verify AWS CLI can access the cluster if not using defaults
    if [ "$CLUSTER_NAME" != "your-cluster-name" ] && command -v aws &> /dev/null; then
        if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query 'cluster.name' --output text &>/dev/null; then
            echo "WARNING: Cannot access cluster '$CLUSTER_NAME' in region '$REGION'"
            echo "         Check your AWS credentials and permissions"
        else
            echo "✅ Successfully verified AWS CLI access to cluster '$CLUSTER_NAME'"
        fi
    fi

    if [ $errors -gt 0 ]; then
        echo "❌ Configuration validation failed with $errors error(s)"
        return 1
    fi

    echo "✅ Configuration validation successful"
    return 0
}

# Function to display configuration
display_config() {
    # Determine configuration sources
    local cluster_source="default"
    if [ -n "${EKS_CLUSTER_NAME}" ]; then
        cluster_source="environment variable (EKS_CLUSTER_NAME)"
    elif [ "$CLUSTER_NAME" != "your-cluster-name" ] && command -v kubectl &> /dev/null; then
        cluster_source="kubeconfig current-context"
    fi

    local region_source="default"
    if [ -n "${AWS_REGION}" ]; then
        region_source="environment variable (AWS_REGION)"
    elif [ -n "${AWS_DEFAULT_REGION}" ]; then
        region_source="environment variable (AWS_DEFAULT_REGION)"
    elif [ "$REGION" != "us-east-1" ] && command -v kubectl &> /dev/null; then
        region_source="extracted from kubeconfig"
    fi

    local nodegroup_source="default"
    if [ -n "${EKS_NODEGROUP_NAME}" ]; then
        nodegroup_source="environment variable (EKS_NODEGROUP_NAME)"
    elif [ "$NODEGROUP_NAME" != "your-nodegroup-name" ]; then
        nodegroup_source="auto-detected from cluster"
    fi

    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║         KUBERNETES HEALTH CHECK CONFIGURATION SUMMARY          ║
╚════════════════════════════════════════════════════════════════╝

Cluster Information:
  • Cluster Name:         $CLUSTER_NAME (source: $cluster_source)
  • Region:               $REGION (source: $region_source)
  • Node Group:           $NODEGROUP_NAME (source: $nodegroup_source)
  • Current Version:      $(get_current_version)

Node Configuration:
  • Instance Types:       $INSTANCE_TYPES
  • AMI Type:             $AMI_TYPE
  • Desired Size:         $DESIRED_SIZE
  • Min Size:             $MIN_SIZE
  • Max Size:             $MAX_SIZE

Health Check Options:
  • Dry Run Mode:         $DRY_RUN
  • Verbose Logging:      $VERBOSE

Output:
  • Log File:             $LOG_FILE

EOF
}

# Function to get current cluster version
get_current_version() {
    aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
        --query 'cluster.version' --output text 2>/dev/null || echo "N/A"
}

# Export all variables for use in scripts
export CLUSTER_NAME
export REGION
export NODEGROUP_NAME
export DESIRED_SIZE
export MIN_SIZE
export MAX_SIZE
export INSTANCE_TYPES
export AMI_TYPE
export DRY_RUN
export IGNORE_DAEMONSETS
export DELETE_LOCAL_STORAGE
export FORCE_DELETE
export ENABLE_NOTIFICATIONS
export WEBHOOK_URL
export VERBOSE
export LOG_DIR
export LOG_FILE

# ==================== HELPER FUNCTIONS ====================

# Log function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Log info
log_info() {
    log "INFO" "$@"
}

# Log error
log_error() {
    log "ERROR" "$@"
}

# Log warning
log_warn() {
    log "WARN" "$@"
}

# Log success
log_success() {
    log "SUCCESS" "$@"
}

# Get AMI information for a node
get_node_ami_info() {
    local node_name=$1
    local instance_id=$(kubectl get node "$node_name" -o jsonpath='{.spec.providerID}' | cut -d '/' -f5)

    if [ -n "$instance_id" ]; then
        # Get AMI ID and Name from AWS
        local ami_info=$(aws ec2 describe-instances --instance-ids "$instance_id" --region "$REGION" \
            --query 'Reservations[0].Instances[0].{ImageId:ImageId,Platform:Platform,InstanceType:InstanceType}' --output json 2>/dev/null)

        if [ -n "$ami_info" ] && [ "$ami_info" != "null" ]; then
            local ami_id=$(echo "$ami_info" | jq -r '.ImageId')
            local platform=$(echo "$ami_info" | jq -r '.Platform // "linux"')
            local instance_type=$(echo "$ami_info" | jq -r '.InstanceType')

            # Get AMI name
            local ami_name=$(aws ec2 describe-images --image-ids "$ami_id" --region "$REGION" \
                --query 'Images[0].Name' --output text 2>/dev/null || echo "N/A")

            # Detect if this is AL2 or AL2023
            local os_version="Unknown"
            local status_icon=""

            if [[ "$ami_name" == *"al2023"* || "$ami_name" == *"AL2023"* ]]; then
                os_version="Amazon Linux 2023"
                status_icon="✅"
                return 0  # AL2023
            elif [[ "$ami_name" == *"al2"* || "$ami_name" == *"AL2"* ]]; then
                os_version="Amazon Linux 2"
                status_icon="⚠️"
                log_warn "Node $node_name is running Amazon Linux 2, which is deprecated for Kubernetes 1.33+"
                return 1  # AL2
            else
                os_version="Unknown"
                status_icon=""
                return 2  # Unknown
            fi
        else
            return 3  # Error
        fi
    else
        return 3  # Error
    fi
}

# Display AMI information for all nodes in a table format
display_node_ami_table() {
    # Initialize counters
    AL2023_NODES=0
    AL2_NODES=0
    UBUNTU_NODES=0
    UNKNOWN_NODES=0
    ERROR_NODES=0

    # Initialize output capture variable
    NODE_AMI_TABLE_OUTPUT=""

    # Get node information directly from kubectl in a format we can parse
    local node_info=$(kubectl get nodes -o wide 2>/dev/null)

    if [ -z "$node_info" ]; then
        NODE_AMI_TABLE_OUTPUT="═══════════════════════════════════════════════════════════════════════════════════════════════════
No nodes found in the cluster
═══════════════════════════════════════════════════════════════════════════════════════════════════"
        echo "$NODE_AMI_TABLE_OUTPUT"
        export AL2023_NODES=0
        export AL2_NODES=0
        export UBUNTU_NODES=0
        export UNKNOWN_NODES=0
        export ERROR_NODES=0
        export NODE_AMI_TABLE_OUTPUT
        return
    fi

    # Get all node names
    local node_names=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null)
    local node_count=$(echo "$node_names" | wc -w)

    # Start building the output
    NODE_AMI_TABLE_OUTPUT="═══════════════════════════════════════════════════════════════════════════════════════════════════
NODE AMI INVENTORY (Total: $node_count nodes)
═══════════════════════════════════════════════════════════════════════════════════════════════════
"

    # Display header to console
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "NODE AMI INVENTORY (Total: $node_count nodes)"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    # Process each node individually to avoid subshell issues with counters
    local counter=1
    for name in $node_names; do
        # Get OS info directly from kubectl
        local os_info=$(kubectl get node "$name" -o jsonpath='{.status.nodeInfo.osImage}' 2>/dev/null)
        local k8s_version=$(kubectl get node "$name" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)
        local ready_status=$(kubectl get node "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        local ready_message="Ready"
        if [ "$ready_status" != "True" ]; then
            ready_message="Not Ready"
        fi

        # Get instance type if possible
        local instance_id=$(kubectl get node "$name" -o jsonpath='{.spec.providerID}' 2>/dev/null | cut -d '/' -f5)
        local instance_type="N/A"
        local ami_id="N/A"
        local ami_name="N/A"
        local launch_time="N/A"

        if [ -n "$instance_id" ]; then
            # Try to get instance type from AWS
            local aws_info=$(aws ec2 describe-instances --instance-ids "$instance_id" --region "$REGION" \
                --query 'Reservations[0].Instances[0].{ImageId:ImageId,InstanceType:InstanceType,LaunchTime:LaunchTime}' --output json 2>/dev/null)

            if [ -n "$aws_info" ] && [ "$aws_info" != "null" ]; then
                instance_type=$(echo "$aws_info" | jq -r '.InstanceType')
                ami_id=$(echo "$aws_info" | jq -r '.ImageId')
                launch_time=$(echo "$aws_info" | jq -r '.LaunchTime')

                # Get AMI name if we have an AMI ID
                if [ "$ami_id" != "N/A" ] && [ "$ami_id" != "null" ]; then
                    ami_name=$(aws ec2 describe-images --image-ids "$ami_id" --region "$REGION" \
                        --query 'Images[0].Name' --output text 2>/dev/null || echo "N/A")
                fi
            fi
        fi

        # Determine OS type and status
        local status_icon="✅"
        local status_message="Compatible with K8s 1.33+"

        if [[ "$os_info" == *"Amazon Linux 2023"* ]]; then
            AL2023_NODES=$((AL2023_NODES + 1))
        elif [[ "$os_info" == *"Amazon Linux 2"* ]]; then
            status_icon="⚠️"
            status_message="AL2 is deprecated for K8s 1.33+"
            AL2_NODES=$((AL2_NODES + 1))
        elif [[ "$os_info" == *"Ubuntu"* ]]; then
            UBUNTU_NODES=$((UBUNTU_NODES + 1))
        else
            status_icon="ℹ️"
            status_message="OS compatibility unknown"
            UNKNOWN_NODES=$((UNKNOWN_NODES + 1))
        fi

        # Display mini-table for each node (both console and capture)
        local node_table="┌─────────────────────────────────────────────────────────────────────────────┐
$(printf "│ NODE %-3d/%-3d: %-61s │" "$counter" "$node_count" "$name")
├─────────────────────────────────────────────────────────────────────────────┤
$(printf "│ %-15s │ %-55s │" "Instance Type" "$instance_type")
$(printf "│ %-15s │ %-55s │" "AMI ID" "$ami_id")
$(printf "│ %-15s │ %-55s │" "AMI Name" "$ami_name")
$(printf "│ %-15s │ %-55s │" "OS Version" "$os_info")
$(printf "│ %-15s │ %-55s │" "K8s Version" "$k8s_version")
$(printf "│ %-15s │ %-55s │" "Status" "$ready_message")
$(printf "│ %-15s │ %-55s │" "Launch Time" "$launch_time")
$(printf "│ %-15s │ %-55s │" "Compatibility" "$status_icon $status_message")
└─────────────────────────────────────────────────────────────────────────────┘
"

        # Output to console
        echo "┌─────────────────────────────────────────────────────────────────────────────┐"
        printf "│ NODE %-3d/%-3d: %-61s │\n" "$counter" "$node_count" "$name"
        echo "├─────────────────────────────────────────────────────────────────────────────┤"
        printf "│ %-15s │ %-55s │\n" "Instance Type" "$instance_type"
        printf "│ %-15s │ %-55s │\n" "AMI ID" "$ami_id"
        printf "│ %-15s │ %-55s │\n" "AMI Name" "$ami_name"
        printf "│ %-15s │ %-55s │\n" "OS Version" "$os_info"
        printf "│ %-15s │ %-55s │\n" "K8s Version" "$k8s_version"
        printf "│ %-15s │ %-55s │\n" "Status" "$ready_message"
        printf "│ %-15s │ %-55s │\n" "Launch Time" "$launch_time"
        printf "│ %-15s │ %-55s │\n" "Compatibility" "$status_icon $status_message"
        echo "└─────────────────────────────────────────────────────────────────────────────┘"
        echo ""

        # Append to output variable
        NODE_AMI_TABLE_OUTPUT+="$node_table"

        ((counter++))
    done

    # Build summary output
    local summary_output="═══════════════════════════════════════════════════════════════════════════════════════════════════
AMI Summary:
  • AL2023 Nodes:     $AL2023_NODES
  • AL2 Nodes:        $AL2_NODES
  • Ubuntu Nodes:     $UBUNTU_NODES
  • Other OS:         $UNKNOWN_NODES
  • Error:            $ERROR_NODES"

    if [ "$AL2_NODES" -gt 0 ]; then
        summary_output="$summary_output

  ⚠️ $AL2_NODES node(s) are running Amazon Linux 2, which is deprecated for Kubernetes 1.33+"
    fi

    # Output summary to console
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "AMI Summary:"
    echo "  • AL2023 Nodes:     $AL2023_NODES"
    echo "  • AL2 Nodes:        $AL2_NODES"
    echo "  • Ubuntu Nodes:     $UBUNTU_NODES"
    echo "  • Other OS:         $UNKNOWN_NODES"
    echo "  • Error:            $ERROR_NODES"

    if [ "$AL2_NODES" -gt 0 ]; then
        echo ""
        echo "  ⚠️ $AL2_NODES node(s) are running Amazon Linux 2, which is deprecated for Kubernetes 1.33+"
    fi

    # Append summary to output variable
    NODE_AMI_TABLE_OUTPUT+="$summary_output"

    # Export values for the calling script
    export AL2023_NODES
    export AL2_NODES
    export UBUNTU_NODES
    export UNKNOWN_NODES
    export ERROR_NODES
    export NODE_AMI_TABLE_OUTPUT
}

# Execute command with logging
execute() {
    local cmd="$@"
    if [ "$VERBOSE" = true ]; then
        log_info "Executing: $cmd"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN: Would execute: $cmd"
        return 0
    fi

    eval "$cmd"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        if [ "$VERBOSE" = true ]; then
            log_info "Command succeeded"
        fi
    else
        log_error "Command failed with exit code $exit_code"
    fi

    return $exit_code
}

# Check AWS CLI availability
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI."
        return 1
    fi
    log_success "AWS CLI found: $(aws --version)"
    return 0
}

# Display deprecated APIs using kubent
display_deprecated_apis() {
    local quick_mode=${1:-false}
    local timeout=${2:-120}

    log_info "Scanning for deprecated Kubernetes APIs using kubent..."

    # Initialize counter and output variable
    local DEPRECATED_COUNT=0
    DEPRECATED_API_OUTPUT=""

    # Check if kubent is installed
    if ! command -v kubent &> /dev/null; then
        log_warn "Kubent not found. Installing kubent..."
        if bash ./install-kubent.sh; then
            log_info "Kubent installed successfully"
        else
            log_error "Failed to install kubent. Please install manually with ./install-kubent.sh"
            DEPRECATED_API_OUTPUT="═══════════════════════════════════════════════════════════════════════════════════════════════════
ERROR: Kubent not found and installation failed
Please install kubent manually with: ./install-kubent.sh
Then run this check again
═══════════════════════════════════════════════════════════════════════════════════════════════════"
            echo "$DEPRECATED_API_OUTPUT"
            export DEPRECATED_COUNT=0
            export DEPRECATED_API_OUTPUT
            return 1
        fi
    else
        log_info "Kube No Trouble (kubent) detected, will use for API deprecation checks"
    fi

    # Build header
    local header_text
    if [ "$quick_mode" = "true" ]; then
        header_text="QUICK DEPRECATED API SCAN (USING KUBENT)"
    else
        header_text="DEPRECATED API SCAN (USING KUBENT)"
    fi

    DEPRECATED_API_OUTPUT="═══════════════════════════════════════════════════════════════════════════════════════════════════
$header_text
═══════════════════════════════════════════════════════════════════════════════════════════════════"

    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "$header_text"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    # Create a temporary directory for results
    local TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    # Run kubent with output format set to json
    log_info "Running kubent for API deprecation analysis..."
    timeout ${timeout}s ~/.local/bin/kubent -o json 2>/dev/null > "$TEMP_DIR/kubent.json" || \
        log_warn "Kubent check timed out after ${timeout} seconds, continuing with partial results"

    # Check if we have valid results
    if [ -s "$TEMP_DIR/kubent.json" ] && jq empty "$TEMP_DIR/kubent.json" 2>/dev/null; then
        # Count deprecated APIs
        DEPRECATED_COUNT=$(jq '. | length' "$TEMP_DIR/kubent.json")

        if [ "$DEPRECATED_COUNT" -gt 0 ]; then
            local deprecated_list=$(jq -r '.[] | "• \(.kind) \(.name) in namespace \(.namespace) uses deprecated API \(.apiVersion)"' "$TEMP_DIR/kubent.json" | \
                sed 's/namespace null/cluster scope/g')

            DEPRECATED_API_OUTPUT="$DEPRECATED_API_OUTPUT
⚠️ Found $DEPRECATED_COUNT deprecated API usage(s) in your cluster

$deprecated_list

Migration recommendations:
  1. Use 'kubectl convert' to update manifests to newer API versions
  2. Update Helm charts and values to use supported API versions
  3. Check custom resources and operators for compatibility
  4. Test all changes in a non-production environment first"

            echo "⚠️ Found $DEPRECATED_COUNT deprecated API usage(s) in your cluster"
            echo ""
            echo "$deprecated_list"
            echo ""
            echo "Migration recommendations:"
            echo "  1. Use 'kubectl convert' to update manifests to newer API versions"
            echo "  2. Update Helm charts and values to use supported API versions"
            echo "  3. Check custom resources and operators for compatibility"
            echo "  4. Test all changes in a non-production environment first"
        else
            DEPRECATED_API_OUTPUT="$DEPRECATED_API_OUTPUT
✅ No deprecated APIs found in the cluster"
            echo "✅ No deprecated APIs found in the cluster"
        fi
    else
        log_warn "No deprecated APIs found by kubent or kubent output is empty/invalid"
        DEPRECATED_COUNT=0
        DEPRECATED_API_OUTPUT="$DEPRECATED_API_OUTPUT
✅ No deprecated APIs found in the cluster (kubent returned no results)"
        echo "✅ No deprecated APIs found in the cluster"
    fi

    DEPRECATED_API_OUTPUT="$DEPRECATED_API_OUTPUT
═══════════════════════════════════════════════════════════════════════════════════════════════════"

    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    # Export the count and output for the calling script
    export DEPRECATED_COUNT
    export DEPRECATED_API_OUTPUT

    return 0
}

# Quick offline check for deprecated APIs using cached kubectl data
quick_offline_deprecated_check() {
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "OFFLINE DEPRECATED API CHECK (using cached data if available)"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    # Check kubectl cache directory
    local cache_dir="$HOME/.kube/cache"
    if [ -d "$cache_dir" ]; then
        echo "Found kubectl cache directory: $cache_dir"
        find "$cache_dir" -name "*.yaml" -o -name "*.json" 2>/dev/null | head -10 | while read -r file; do
            if [ -f "$file" ]; then
                # Look for apiVersion fields in cached files
                grep -H "apiVersion:" "$file" 2>/dev/null | head -5
            fi
        done
    fi

    # Check for common deprecated API patterns in your Helm values
    echo ""
    echo "Checking for deprecated APIs in Helm charts based on known patterns:"

    # Based on your Helm chart list, let's check for known deprecated APIs
    cat << 'EOF'

Likely deprecated APIs in your cluster based on installed components:

🔍 ISTIO (v1.23.4):
  • Potential: networking.k8s.io/v1beta1 for Gateways/VirtualServices
  • Impact: Medium - Istio often uses beta networking APIs

🔍 AWS LOAD BALANCER CONTROLLER (v2.11.0):
  • Potential: networking.k8s.io/v1beta1 for Ingress resources
  • Impact: High - Critical for ingress traffic

🔍 CALICO (v3.27.0):
  • Potential: policy/v1beta1 for NetworkPolicies
  • Impact: Medium - Network security policies

🔍 PROMETHEUS/GRAFANA:
  • Potential: monitoring.coreos.com/v1beta1 for ServiceMonitors
  • Impact: Low - Monitoring configurations

🔍 EXTERNAL SECRETS (v0.13.0):
  • Potential: external-secrets.io/v1beta1 for SecretStores
  • Impact: Medium - Secret management

EOF

    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "⚠️  To get accurate results, please:"
    echo "   1. Refresh your AWS SSO session: aws sso login --profile <your-profile>"
    echo "   2. Run: display_deprecated_apis false"
    echo "   3. Or install kubent: curl -L https://github.com/doitintl/kube-no-trouble/releases/latest/download/kubent-linux-amd64.tar.gz | tar xz"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
}

# Display Helm charts inventory
display_helm_charts() {
    if ! command -v helm &> /dev/null; then
        log_warn "Helm not found. Cannot display Helm charts inventory."
        echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
        echo "Helm CLI not installed or not found in PATH."
        echo "To install Helm, follow instructions at: https://helm.sh/docs/intro/install/"
        echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
        return 0
    fi

    log_info "Collecting Helm charts inventory..."

    # Get all helm releases across all namespaces
    local all_releases=$(helm list --all-namespaces --output json 2>/dev/null)

    if [ -z "$all_releases" ] || [ "$all_releases" == "[]" ]; then
        echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
        echo "No Helm charts found in the cluster"
        echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
        return 0
    fi

    # Log the first chart for debugging purposes
    if [ "$VERBOSE" = true ]; then
        local first_chart=$(echo "$all_releases" | jq -c '.[0]' 2>/dev/null)
        if [ -n "$first_chart" ]; then
            log_info "Sample Helm chart data: $first_chart"
        fi
    fi

    # Count total releases
    local total_releases=$(echo "$all_releases" | jq '. | length')
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "HELM CHARTS INVENTORY (Total: $total_releases charts)"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    # Parse and display each release as a mini-table
    local counter=1
    echo "$all_releases" | jq -c '.[]' | while read -r release; do
        local namespace=$(echo "$release" | jq -r '.namespace')
        local name=$(echo "$release" | jq -r '.name')
        local chart=$(echo "$release" | jq -r '.chart')
        local app_version=$(echo "$release" | jq -r '.app_version')
        local status=$(echo "$release" | jq -r '.status')
        local updated=$(echo "$release" | jq -r '.updated')

        # Extract chart version from chart field (format: chart-name-version)
        local chart_version=""
        if [[ "$chart" =~ -([0-9]+\.[0-9]+\.[0-9]+.*$) ]]; then
            chart_version="${BASH_REMATCH[1]}"
        elif [[ "$chart" =~ -v([0-9]+\.[0-9]+\.[0-9]+.*$) ]]; then
            chart_version="${BASH_REMATCH[1]}"
        elif [[ "$chart" =~ -([0-9]+\.[0-9]+$) ]]; then
            chart_version="${BASH_REMATCH[1]}"
        else
            chart_version="$chart"
        fi

        # Display mini-table for each chart
        echo "┌─────────────────────────────────────────────────────────────────────────────┐"
        printf "│ CHART %-3d/%-3d: %-60s │\n" "$counter" "$total_releases" "$name"
        echo "├─────────────────────────────────────────────────────────────────────────────┤"
        printf "│ %-15s │ %-55s │\n" "Namespace" "$namespace"
        printf "│ %-15s │ %-55s │\n" "Chart" "$chart"
        printf "│ %-15s │ %-55s │\n" "Chart Version" "$chart_version"
        printf "│ %-15s │ %-55s │\n" "App Version" "$app_version"
        printf "│ %-15s │ %-55s │\n" "Status" "$status"
        printf "│ %-15s │ %-55s │\n" "Last Updated" "$updated"
        echo "└─────────────────────────────────────────────────────────────────────────────┘"
        echo ""

        ((counter++))
    done

    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    # Count by status
    local deployed_charts=$(echo "$all_releases" | jq '[.[] | select(.status == "deployed")] | length')
    local failed_charts=$(echo "$all_releases" | jq '[.[] | select(.status == "failed")] | length')
    local pending_charts=$(echo "$all_releases" | jq '[.[] | select(.status == "pending")] | length')

    echo "Total Helm Charts: $total_releases"
    echo "  • Deployed: $deployed_charts"

    if [ "$failed_charts" -gt 0 ]; then
        echo "  • Failed:   $failed_charts ⚠️"
    else
        echo "  • Failed:   $failed_charts"
    fi

    if [ "$pending_charts" -gt 0 ]; then
        echo "  • Pending:  $pending_charts ⚠️"
    else
        echo "  • Pending:  $pending_charts"
    fi

    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    return 0
}

# Check kubectl availability
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        return 1
    fi
    log_success "kubectl found: $(kubectl version --client --short 2>/dev/null)"
    return 0
}

# Check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        return 1
    fi
    local account=$(aws sts get-caller-identity --query 'Account' --output text)
    log_success "AWS credentials valid (Account: $account)"
    return 0
}

# Verify cluster access
verify_cluster_access() {
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster. Check kubeconfig configuration."
        return 1
    fi
    log_success "Kubernetes cluster accessible"
    return 0
}

# Send notification (optional)
send_notification() {
    if [ "$ENABLE_NOTIFICATIONS" != true ] || [ -z "$WEBHOOK_URL" ]; then
        return 0
    fi

    local message=$1
    local status=${2:-info}

    if command -v jq &> /dev/null; then
        curl -X POST "$WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"text\": \"[$status] $message\"}" \
            2>/dev/null || log_warn "Failed to send notification"
    fi
}

# Pure kubectl-based deprecated API scanner (no external tools needed)
# This is more reliable than kubent/pluto which may be outdated
scan_deprecated_apis_kubectl() {
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "PURE KUBECTL DEPRECATED API SCANNER"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    local FOUND_COUNT=0
    local TEMP_FILE=$(mktemp)

    # Common resource types to check
    local RESOURCE_TYPES=(
        "deployments"
        "statefulsets"
        "daemonsets"
        "replicasets"
        "ingresses"
        "networkpolicies"
        "poddisruptionbudgets"
        "horizontalpodautoscalers"
        "cronjobs"
        "jobs"
    )

    echo "Scanning all namespaces for deprecated API usage..."
    echo ""

    # Check each resource type
    for resource in "${RESOURCE_TYPES[@]}"; do
        echo -n "Checking $resource... "

        # Get all instances of this resource type across all namespaces
        local result=$(kubectl get "$resource" --all-namespaces -o json 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$result" ]; then
            # Extract apiVersion from each resource
            local apis=$(echo "$result" | jq -r '.items[]? | "\(.apiVersion) \(.kind) \(.metadata.name) \(.metadata.namespace)"' 2>/dev/null)

            if [ -n "$apis" ]; then
                # Check for deprecated API versions
                echo "$apis" | while read -r line; do
                    local api_version=$(echo "$line" | awk '{print $1}')

                    # Check if this API version is deprecated
                    case "$api_version" in
                        *beta1|*beta2|*alpha*)
                            echo "$line" >> "$TEMP_FILE"
                            ;;
                    esac
                done

                local count=$(echo "$apis" | wc -l)
                echo "found $count instances"
            else
                echo "none found"
            fi
        else
            echo "none found"
        fi
    done

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    if [ -s "$TEMP_FILE" ]; then
        echo "⚠️  DEPRECATED APIs FOUND:"
        echo ""

        printf "%-35s %-20s %-30s %-20s\n" "API VERSION" "KIND" "NAME" "NAMESPACE"
        echo "───────────────────────────────────────────────────────────────────────────────────────────────"

        sort -u "$TEMP_FILE" | while read -r line; do
            local api=$(echo "$line" | awk '{print $1}')
            local kind=$(echo "$line" | awk '{print $2}')
            local name=$(echo "$line" | awk '{print $3}')
            local namespace=$(echo "$line" | awk '{print $4}')

            # Truncate long names
            if [ ${#name} -gt 28 ]; then
                name="${name:0:25}..."
            fi
            if [ ${#namespace} -gt 18 ]; then
                namespace="${namespace:0:15}..."
            fi

            printf "%-35s %-20s %-30s %-20s\n" "$api" "$kind" "$name" "$namespace"
            ((FOUND_COUNT++))
        done

        echo ""
        echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
        echo "Total deprecated API instances found: $FOUND_COUNT"
        echo ""
        echo "⚠️  RECOMMENDATIONS:"
        echo "  1. Update these resources to use stable API versions"
        echo "  2. Check Helm chart values for API version overrides"
        echo "  3. Test changes in a non-production environment first"
        echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
    else
        echo "✅ No deprecated APIs found!"
        echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
    fi

    rm -f "$TEMP_FILE"
}

# ==================== HTML REPORT GENERATION ====================

# Initialize HTML report
init_html_report() {
    local report_title="$1"
    local script_name="$2"

    HTML_REPORT_FILE="${REPORTS_DIR}/$(basename "$script_name" .sh)-$(date +%Y%m%d-%H%M%S).html"
    HTML_REPORT_CONTENT=""
    HTML_REPORT_START_TIME=$(date +%s)

    cat > "$HTML_REPORT_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kubernetes Health Check Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            line-height: 1.6;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #232526 0%, #414345 100%);
            color: white;
            padding: 30px;
            border-bottom: 4px solid #667eea;
        }
        .header h1 {
            font-size: 28px;
            margin-bottom: 10px;
        }
        .header .meta {
            display: flex;
            gap: 30px;
            margin-top: 15px;
            font-size: 14px;
            opacity: 0.9;
        }
        .header .meta-item {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .content {
            padding: 30px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .summary-card {
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid;
        }
        .summary-card.success {
            background: #ecfdf5;
            border-color: #10b981;
        }
        .summary-card.warning {
            background: #fffbeb;
            border-color: #f59e0b;
        }
        .summary-card.error {
            background: #fef2f2;
            border-color: #ef4444;
        }
        .summary-card.info {
            background: #eff6ff;
            border-color: #3b82f6;
        }
        .summary-card h3 {
            font-size: 14px;
            color: #64748b;
            margin-bottom: 8px;
        }
        .summary-card .value {
            font-size: 24px;
            font-weight: 700;
        }
        .section {
            margin-bottom: 30px;
        }
        .section-title {
            font-size: 20px;
            font-weight: 700;
            color: #1e293b;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid #e2e8f0;
        }
        .output-box {
            background: #1e293b;
            color: #e2e8f0;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            overflow-x: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
            max-height: 600px;
            overflow-y: auto;
        }
        .output-box .success { color: #10b981; }
        .output-box .warning { color: #f59e0b; }
        .output-box .error { color: #ef4444; }
        .output-box .info { color: #3b82f6; }
        .step {
            margin-bottom: 25px;
            padding: 20px;
            background: #f8fafc;
            border-radius: 8px;
            border-left: 4px solid #3b82f6;
        }
        .step-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        .step-title {
            font-weight: 600;
            font-size: 16px;
            color: #1e293b;
        }
        .badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
        }
        .badge.success {
            background: #10b981;
            color: white;
        }
        .badge.warning {
            background: #f59e0b;
            color: white;
        }
        .badge.error {
            background: #ef4444;
            color: white;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
            background: white;
            border-radius: 8px;
            overflow: hidden;
        }
        th {
            background: #f1f5f9;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #475569;
            border-bottom: 2px solid #e2e8f0;
        }
        td {
            padding: 12px;
            border-bottom: 1px solid #e2e8f0;
        }
        tr:hover {
            background: #f8fafc;
        }
        .footer {
            background: #f8fafc;
            padding: 20px 30px;
            border-top: 1px solid #e2e8f0;
            text-align: center;
            color: #64748b;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>REPORT_TITLE</h1>
            <div class="meta">
                <div class="meta-item">
                    <span>📅</span>
                    <span>REPORT_DATE</span>
                </div>
                <div class="meta-item">
                    <span>🖥️</span>
                    <span>CLUSTER_NAME</span>
                </div>
                <div class="meta-item">
                    <span>🌍</span>
                    <span>REGION_NAME</span>
                </div>
            </div>
        </div>
        <div class="content">
EOF

    # Replace placeholders
    sed -i "s/REPORT_TITLE/$report_title/g" "$HTML_REPORT_FILE"
    sed -i "s/REPORT_DATE/$(date '+%Y-%m-%d %H:%M:%S')/g" "$HTML_REPORT_FILE"
    sed -i "s/CLUSTER_NAME/$CLUSTER_NAME/g" "$HTML_REPORT_FILE"
    sed -i "s/REGION_NAME/$REGION/g" "$HTML_REPORT_FILE"

    log_info "HTML report initialized: $HTML_REPORT_FILE"
}

# Add summary cards to HTML report
add_html_summary() {
    local title="$1"
    local value="$2"
    local status="${3:-info}"  # success, warning, error, info

    cat >> "$HTML_REPORT_FILE" << EOF
            <div class="summary-card $status">
                <h3>$title</h3>
                <div class="value">$value</div>
            </div>
EOF
}

# Start summary section
start_html_summary() {
    cat >> "$HTML_REPORT_FILE" << 'EOF'
            <div class="summary">
EOF
}

# End summary section
end_html_summary() {
    cat >> "$HTML_REPORT_FILE" << 'EOF'
            </div>
EOF
}

# Add section to HTML report
add_html_section() {
    local section_title="$1"
    local content="$2"

    cat >> "$HTML_REPORT_FILE" << EOF
            <div class="section">
                <div class="section-title">$section_title</div>
                <div class="output-box">$(echo "$content" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</div>
            </div>
EOF
}

# Add step to HTML report
add_html_step() {
    local step_title="$1"
    local step_status="$2"  # success, warning, error
    local step_content="$3"

    cat >> "$HTML_REPORT_FILE" << EOF
            <div class="step">
                <div class="step-header">
                    <div class="step-title">$step_title</div>
                    <div class="badge $step_status">$step_status</div>
                </div>
                <div class="output-box">$(echo "$step_content" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</div>
            </div>
EOF
}

# Finalize HTML report
finalize_html_report() {
    local overall_status="${1:-success}"

    local end_time=$(date +%s)
    local duration=$((end_time - HTML_REPORT_START_TIME))
    local duration_formatted=$(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

    cat >> "$HTML_REPORT_FILE" << EOF
        </div>
        <div class="footer">
            <p><strong>Report generated:</strong> $(date '+%Y-%m-%d %H:%M:%S') | <strong>Duration:</strong> $duration_formatted | <strong>Status:</strong> $overall_status</p>
            <p>Kubernetes Health Check Toolkit</p>
        </div>
    </div>
</body>
</html>
EOF

    log_success "HTML report saved: $HTML_REPORT_FILE"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "📊 HTML Report Generated"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Location: $HTML_REPORT_FILE"
    echo ""
    echo "To view the report:"
    echo "  • Open in browser: file://$HTML_REPORT_FILE"
    echo "  • Or run: xdg-open $HTML_REPORT_FILE"
    echo "═══════════════════════════════════════════════════════════════"
}

echo "✅ Configuration loaded successfully from $(basename "$0")"
