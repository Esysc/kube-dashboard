# Kubernetes Health Check Scripts

This directory contains a collection of scripts for performing health checks on Kubernetes clusters, primarily focused on Amazon EKS.

## 🚀 Quick Start

### Run a comprehensive health check
```bash
./health-check.sh
```

### List all EKS clusters
```bash
# List all EKS clusters across all regions
./list-eks-clusters.sh

# List clusters in a specific region
./list-eks-clusters.sh us-east-1
```

## 📁 Directory Structure

```
scripts/
├── README.md                    # This file
├── config.sh                    # Configuration for all scripts
├── health-check.sh              # Comprehensive cluster health check
├── list-eks-clusters.sh         # List all EKS clusters and versions
├── install-kubent.sh            # Installs the 'kubent' tool for deprecated API checks
├── html-report-template.sh      # A template for creating new reports
├── logs/                        # Log files from script executions
└── reports/                     # HTML reports from script executions
```

## ⚙️ Configuration

### Environment Variables (Recommended)

You can configure the scripts using environment variables:

```bash
# Set these environment variables before running scripts
export EKS_CLUSTER_NAME="your-cluster-name"
export AWS_REGION="us-east-1"
export EKS_NODEGROUP_NAME="your-nodegroup"

# Then run the scripts
./health-check.sh
```

### Auto-Detection

The scripts will attempt to auto-detect configuration:
- Cluster name from kubectl current-context
- Region from AWS environment variables or kubectl context
- Nodegroup name from the first nodegroup in the cluster

### Manual Configuration

Alternatively, edit `config.sh` directly:

```bash
# Cluster Configuration
CLUSTER_NAME="your-cluster-name"
REGION="us-east-1"
NODEGROUP_NAME="your-nodegroup"

# Node Configuration
DESIRED_SIZE=3
MIN_SIZE=1
MAX_SIZE=5
INSTANCE_TYPES="t3.large"
```

## 📊 Health Checks

The `health-check.sh` script performs a number of checks, including:
- Cluster and Node Status
- Pod Health (Running, Pending, Failed)
- Resource Utilization (CPU/Memory)
- Deprecated API usage (via `kubent`)
- EKS Addon Status
- And more...

## 🔍 Pre-Checklist

Before running the health check:

- [ ] Verify AWS credentials: `aws sts get-caller-identity`
- [ ] Confirm kubectl context: `kubectl current-context`
- [ ] Ensure you have permissions to describe EKS clusters and nodes.

## 🔐 Security & Best Practices

```bash
# Check for deprecated APIs
./install-kubent.sh
~/.local/bin/kubent

# Review security policies
kubectl get networkpolicies --all-namespaces
kubectl get podsecuritypolicies
```

## 📈 Monitoring & Logs

All scripts log to the `logs/` directory with timestamps:

```bash
# View health check logs
tail -f logs/health-check-*.log

# Check for errors in any log file
grep "ERROR" logs/*.log
```

## ⚠️ Important Notes

### Deprecated API Scanner
- The `health-check.sh` script uses `kubent` to find deprecated APIs.
- You may need to run `./install-kubent.sh` first.

## 🆘 Troubleshooting

### Cannot access cluster
```bash
# Check status
aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.status' --output text

# If it fails, check your AWS credentials and permissions.
```

### Nodes Not Ready
```bash
# Check node group status
aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODEGROUP_NAME --region $AWS_REGION --query 'nodegroup.health' --output table

# Check node logs
kubectl describe node <node-name>
```

### Pods Stuck in Pending
```bash
# Check events
kubectl describe pod <pod-name> -n <namespace>

# Check resource availability
kubectl top nodes
kubectl top pods --all-namespaces
```

## 📞 Support & References

### AWS Documentation
- [EKS Kubernetes Versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [EKS User Guide](https://docs.aws.amazon.com/eks/)

### Kubernetes Documentation
- [Kubernetes API Deprecations](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

## 📝 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-10-28 | Initial release of health check scripts |

## 📄 License

These scripts are provided as-is for EKS cluster health checks.

---

## 📊 HTML Reports

All scripts generate HTML reports with:
- Visual status indicators
- Comprehensive details
- Easy browser viewing

**View Reports:**
You can open the `.html` files in the `reports/` directory in any web browser.

---

## Next Steps

1. **Review**: Read through this README.
2. **Configure**: Edit `config.sh` with your cluster details if auto-detection is not sufficient.
3. **Run**: Execute `./health-check.sh`.
4. **Reports**: View the generated HTML report in the `reports/` directory.
