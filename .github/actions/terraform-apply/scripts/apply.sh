#!/usr/bin/env bash
set -euo pipefail

: "${TF_PLAN_PATH:?Missing Terraform plan path}"

echo '--- Terraform version ---'
terraform version

echo '--- Initialize backend ---'
terraform init -input=false -lockfile=readonly -no-color

echo '--- Apply approved plan ---'
# A saved plan carries its own approval, so no -auto-approve is used here.
terraform apply -input=false -no-color "$TF_PLAN_PATH"
