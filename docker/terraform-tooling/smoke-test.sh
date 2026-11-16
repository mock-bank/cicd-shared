#!/usr/bin/env bash
set -euo pipefail

terraform version
tflint --version
checkov --version
jq --version
python --version

printf '\nTerraform tooling image smoke test passed.\n'