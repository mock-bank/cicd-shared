#!/usr/bin/env bash
set -euo pipefail

: "${CHECKOV_REPORT_PATH:?Missing Checkov report directory}"

echo '--- Checkov Terraform scan ---'
# Fail the job on findings; repositories can tune results with .checkov.yml.
checkov \
  --directory . \
  --framework terraform \
  --output cli \
  --output json \
  --output-file-path "console,${CHECKOV_REPORT_PATH}/report.json" \
  --quiet \
  --compact

[[ -s "${CHECKOV_REPORT_PATH}/report.json" ]] || { echo 'Checkov did not produce a report' >&2; exit 1; }
echo 'Checkov scan completed.'
