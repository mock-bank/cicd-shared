#!/usr/bin/env bash
set -euo pipefail

echo '--- Terraform version ---'
terraform version

echo '--- Format check ---'
terraform fmt -check -recursive -no-color

echo '--- Initialize without remote backend ---'
# Projects must commit .terraform.lock.hcl so dependency selections are reviewed.
terraform init -backend=false -input=false -lockfile=readonly -no-color

echo '--- Terraform validate ---'
terraform validate -no-color

if [[ "${ENABLE_TFLINT:-true}" == 'true' ]]; then
  echo '--- TFLint initialization ---'
  tflint --init
  echo '--- TFLint checks ---'
  tflint --no-color
fi

echo 'Terraform validation completed.'