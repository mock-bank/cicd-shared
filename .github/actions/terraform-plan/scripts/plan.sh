#!/usr/bin/env bash
set -euo pipefail

: "${TF_PLAN_PATH:?Missing Terraform plan path}"

echo '--- Terraform version ---'
terraform version

echo '--- Initialize backend ---'
# Projects must commit .terraform.lock.hcl so dependency selections are reviewed.
terraform init -input=false -lockfile=readonly -no-color

echo '--- Create plan ---'
terraform plan -input=false -no-color -out="$TF_PLAN_PATH"
