# Cluster bootstrap (one-time, per environment)

The Helm chart in `helm/fastapi-service` deploys **this one service**. Two
pieces of cluster-wide infrastructure need to exist first, from public Helm
charts -- install them once per cluster, not per service:

## 1. AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster_name output> \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=<region> \
  --set vpcId=<vpc_id from terraform output>
```

(Attach an IRSA role with the AWS-published `AWSLoadBalancerControllerIAMPolicy`
to the `aws-load-balancer-controller` ServiceAccount, the same way
`infra/terraform/modules/irsa-role` is used for the app -- add a module
instance for it in `live/<env>/main.tf` if you want this Terraform-managed
rather than click-ops.)

## 2. External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set serviceAccount.name=external-secrets
```

Then annotate its ServiceAccount with the `external_secrets_irsa_role_arn`
Terraform output:

```bash
kubectl annotate serviceaccount external-secrets -n external-secrets \
  eks.amazonaws.com/role-arn=<external_secrets_irsa_role_arn output>
```

And create the `ClusterSecretStore` the chart's `ExternalSecret` resources
reference:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: <region>
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

## Then deploy the app

```bash
aws eks update-kubeconfig --name <cluster_name> --region <region>
helm upgrade --install k8s-demo-service infra/k8s/helm/fastapi-service \
  --namespace k8s-demo --create-namespace \
  -f infra/k8s/helm/fastapi-service/values.yaml \
  -f infra/k8s/helm/fastapi-service/values-dev.yaml \
  --set image.repository=<ecr_repository_url output> \
  --set image.tag=<a real tag> \
  --set serviceAccount.roleArn=<app_irsa_role_arn output>
```

This is exactly what `.github/workflows/reusable-deploy.yml` automates in
CI once the GitHub Environment variables described in the top-level
`README.md` are set.
