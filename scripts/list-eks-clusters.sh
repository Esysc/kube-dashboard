#!/bin/bash

################################################################################
# List EKS Clusters Script
# This script lists all EKS clusters across regions and their current versions
################################################################################

# Function to display usage
display_usage() {
    cat << EOF
Usage: $(basename "$0") [REGION]

Lists all EKS clusters and their versions.

Arguments:
  REGION    Optional: Specify a single AWS region to check (e.g., us-east-1)
            If not provided, all enabled regions will be checked

Options:
  --help    Display this help message and exit

Examples:
  $(basename "$0")              # Check all regions
  $(basename "$0") us-east-1    # Check only us-east-1 region
EOF
    exit 0
}

# Check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    display_usage
fi

# Source configuration
source "$(dirname "$0")/config.sh"

# Function to display script header
display_header() {
    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║         EKS CLUSTERS INVENTORY                                 ║
╚════════════════════════════════════════════════════════════════╝

EOF
}

# Function to list EKS clusters in a specific region
list_clusters_in_region() {
    local region=$1
    local clusters_json

    log_info "Checking for EKS clusters in region: $region"

    # Get clusters in the region
    clusters_json=$(aws eks list-clusters --region "$region" --output json 2>/dev/null)

    # Check if command was successful
    if [ $? -ne 0 ]; then
        log_error "Failed to list clusters in region $region"
        return 1
    fi

    # Extract cluster names
    local clusters=$(echo "$clusters_json" | jq -r '.clusters[]' 2>/dev/null)

    # If no clusters found, return
    if [ -z "$clusters" ]; then
        log_info "No EKS clusters found in region $region"
        return 0
    fi

    # Print region header
    echo "Region: $region"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    printf "%-40s %-15s %-20s %-20s\n" "CLUSTER NAME" "VERSION" "STATUS" "CREATED"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"

    # Process each cluster
    for cluster in $clusters; do
        # Get cluster details
        local cluster_info=$(aws eks describe-cluster --name "$cluster" --region "$region" --output json 2>/dev/null)

        if [ $? -eq 0 ]; then
            local version=$(echo "$cluster_info" | jq -r '.cluster.version')
            local status=$(echo "$cluster_info" | jq -r '.cluster.status')
            local created=$(echo "$cluster_info" | jq -r '.cluster.createdAt' | cut -d'T' -f1)

            # Truncate cluster name if too long
            local display_cluster="$cluster"
            if [ ${#display_cluster} -gt 38 ]; then
                display_cluster="${display_cluster:0:35}..."
            fi

            # Print cluster info
            printf "%-40s %-15s %-20s %-20s\n" "$display_cluster" "$version" "$status" "$created"

            # Count clusters by version
            if [ -n "$version" ]; then
                VERSION_COUNTS["$version"]=$((VERSION_COUNTS["$version"] + 1))
            fi

            # Count clusters by status
            if [ -n "$status" ]; then
                STATUS_COUNTS["$status"]=$((STATUS_COUNTS["$status"] + 1))
            fi

            # Increment total count
            TOTAL_CLUSTERS=$((TOTAL_CLUSTERS + 1))
        else
            log_error "Failed to get details for cluster $cluster in region $region"
        fi
    done

    echo ""
    return 0
}

# Function to display summary
display_summary() {
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "EKS CLUSTERS SUMMARY"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "Total Clusters: $TOTAL_CLUSTERS"

    # Display version counts
    echo ""
    echo "Clusters by Kubernetes Version:"
    for version in "${!VERSION_COUNTS[@]}"; do
        echo "  • $version: ${VERSION_COUNTS[$version]}"
    done

    # Display status counts
    echo ""
    echo "Clusters by Status:"
    for status in "${!STATUS_COUNTS[@]}"; do
        if [ "$status" == "ACTIVE" ]; then
            echo "  • $status: ${STATUS_COUNTS[$status]} ✅"
        elif [ "$status" == "CREATING" ]; then
            echo "  • $status: ${STATUS_COUNTS[$status]} 🔄"
        elif [ "$status" == "FAILED" ]; then
            echo "  • $status: ${STATUS_COUNTS[$status]} ❌"
        else
            echo "  • $status: ${STATUS_COUNTS[$status]}"
        fi
    done

    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════"
}

# Initialize global counters
declare -A VERSION_COUNTS
declare -A STATUS_COUNTS
TOTAL_CLUSTERS=0

# Main function
main() {
    display_header

    # Check AWS CLI
    if ! check_aws_cli; then
        log_error "AWS CLI is required for this script"
        exit 1
    fi

    # Check if a specific region was provided
    if [ -n "$1" ]; then
        REGIONS="$1"
        log_info "Checking EKS clusters in specified region: $REGIONS"
    else
        # Get all enabled regions
        log_info "Getting list of enabled AWS regions..."
        REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null)

        if [ $? -ne 0 ]; then
            log_error "Failed to get AWS regions. Check your AWS credentials."
            exit 1
        fi

        log_info "Found $(echo "$REGIONS" | wc -w) enabled AWS regions"
    fi

    # Process each region
    for region in $REGIONS; do
        list_clusters_in_region "$region"
    done

    # Display summary
    display_summary

    log_success "EKS clusters inventory completed"
    return 0
}

# Execute main function
main "$@"
