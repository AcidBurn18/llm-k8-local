# Cloud Portability Note

> One-page mapping of local components to their managed-cloud equivalents.
> This is documentation only — nothing here is implemented.

## Component Mapping

| Local Component | What It Does Here | Managed Cloud Equivalent | What Would Change |
|----------------|-------------------|--------------------------|-------------------|
| **Kind cluster** | K8s cluster running inside Docker on laptop | GKE Autopilot / EKS / AKS | Replace `kind` Terraform provider with `google_container_cluster` / `aws_eks_cluster`. Node pools, autoscaling, and upgrades become managed. |
| **Local Docker images** | Images loaded with `kind load docker-image` | Artifact Registry (GCP) / ECR (AWS) / ACR (Azure) | Add `docker push` step to CI/CD pointing to registry URL. Update `image:` fields in K8s manifests. Set `imagePullPolicy: Always`. Add `imagePullSecrets` if registry is private. |
| **mkcert TLS** | Self-signed certificate trusted locally | ACM (AWS) / Google-managed certs / cert-manager + Let's Encrypt | Deploy cert-manager into the cluster. Annotate the Ingress with `cert-manager.io/cluster-issuer`. Certs are issued and renewed automatically. |
| **Kubernetes Secrets** | Secrets stored in etcd (base64, not encrypted by default) | GCP Secret Manager / AWS Secrets Manager / HashiCorp Vault | Deploy External Secrets Operator. Define `ExternalSecret` CRDs that sync from Secret Manager into K8s Secrets. Application code stays unchanged. |
| **PVC (Kind hostPath)** | Model weights stored on the local node filesystem | GCS (GCP) / S3 (AWS) for weights; Filestore / EFS for ReadWriteMany PVC | Use a `StorageClass` backed by cloud disk (ReadWriteOnce) or cloud file store (ReadWriteMany). Or download weights from cloud storage bucket at startup (swap HuggingFace download for `gsutil cp` / `aws s3 cp`). |
| **`kubectl logs` / Loki** | Lightweight local log aggregation | Cloud Logging (GCP) / CloudWatch (AWS) | Deploy Fluent Bit DaemonSet with a cloud output plugin. Logs flow automatically to the managed log service. No Loki needed. |
| **Prometheus on-cluster** | Self-hosted metrics and alerting | Google Cloud Monitoring / Amazon Managed Prometheus / Datadog | Configure Prometheus remote-write to the managed endpoint. Or replace Prometheus with the cloud-native agent. Grafana can connect to CloudWatch / Cloud Monitoring as a data source. |
| **Nginx Ingress + NodePort** | Routes external traffic to gateway | Cloud Load Balancer (GCP: GLB, AWS: ALB/NLB) | Use a cloud-native `IngressClass` (e.g., `gce` on GKE, `alb` on EKS). The cloud provisions a real load balancer with a public IP. TLS is handled by ACM / Google-managed certs. |
| **Kind NetworkPolicies** | Enforced by the kindnet CNI plugin | Same K8s NetworkPolicy API — supported by GKE Dataplane V2, AWS VPC CNI, etc. | No change to the NetworkPolicy YAML. Just ensure the cloud cluster's CNI supports NetworkPolicy (most do by default now). |
| **Terraform local state** | `terraform.tfstate` stored on disk | GCS backend / S3 backend with DynamoDB locking | Add a `backend "gcs" {}` or `backend "s3" {}` block to `providers.tf`. Run `terraform init -migrate-state` once. |

## What Would Actually Change in the Code

1. **Terraform**: Swap provider from `tehcyx/kind` → `hashicorp/google` (or `hashicorp/aws`). Add VPC, subnets, cluster resources.
2. **CI/CD Makefile**: Replace `kind load docker-image` with `docker push <registry>/<image>`. Add authentication step (`gcloud auth configure-docker` or `aws ecr get-login-password`).
3. **K8s manifests**: Update `image:` to use full registry path. Remove `imagePullPolicy: Never`. Add `StorageClass` for cloud disk.
4. **Secrets**: Add External Secrets Operator Helm release to Terraform. Replace `kubectl create secret` with `ExternalSecret` CRDs.
5. **Nothing changes**: Application code (FastAPI services), LLM inference logic, NetworkPolicies, RBAC, HPA, PDB, CronJob — all remain identical.
