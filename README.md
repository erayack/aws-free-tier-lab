# AWS Free Tier Lab

Create temporary EC2, RDS, Lambda and Budget resources for AWS credit activities, then destroy them. These four earned us **$80**. Your account must be eligible; rewards aren't guaranteed. Do Bedrock's activity manually.

## Create

Requires Terraform 1.7+ and AWS credentials with permission to manage these resources, including IAM roles.

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit your account ID, AWS profile and region.
terraform init
terraform plan -out=activities.tfplan
terraform apply activities.tfplan
curl --fail "$(terraform output -raw lambda_url)"
```

## Destroy

```sh
terraform plan -destroy -out=cleanup.tfplan
terraform apply cleanup.tfplan
```

## License

MIT
