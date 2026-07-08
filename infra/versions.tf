terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.53.0" # exact pin — do not use ~> here.
      # Known issue: aws_dynamodb_table GSIs using the new `key_schema` syntax
      # cause perpetual state drift / forced GSI recreation (see hashicorp/
      # terraform-provider-aws #46335, #46513, #46601 — open as of 2026-07).
      # Workaround in effect: use `hash_key` / `range_key` on global_secondary_index
      # blocks, NOT `key_schema`, regardless of provider version.
      # Before bumping this pin, re-check those issues for a confirmed fix,
      # and if bumping, re-verify with `terraform plan` on the Matches table.
    }
  }
}
