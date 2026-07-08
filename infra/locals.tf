locals {
  environment = terraform.workspace
}

# Requires Terraform >= 1.5 (check blocks). Fails plan/apply with a clear
# error if the active workspace isn't one of the expected environments.
check "valid_environment" {
  assert {
    condition     = contains(["dev", "test", "prod"], terraform.workspace)
    error_message = "terraform.workspace must be one of dev, test, prod — currently '${terraform.workspace}'. Run `terraform workspace select <env>` or `terraform workspace new <env>`."
  }
}
