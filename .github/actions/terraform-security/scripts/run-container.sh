#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?Missing GitHub workspace}"
: "${GITHUB_ACTION_PATH:?Missing composite action path}"
: "${GITHUB_OUTPUT:?Missing GitHub output file}"
: "${RUNNER_TEMP:?Missing GitHub runner temp directory}"
: "${TOOLING_IMAGE:?Missing tooling image}"
: "${TF_WORKING_DIRECTORY:?Missing Terraform directory}"

# Refuse tags and other non-immutable references. Also restrict to a GAR registry.
if [[ ! "$TOOLING_IMAGE" =~ ^[a-z][a-z0-9-]*-docker\.pkg\.dev/[a-z][a-z0-9-]*/[a-z][a-z0-9_-]*/[a-zA-Z0-9_.-]+@sha256:[a-fA-F0-9]{64}$ ]]; then
  echo 'tooling-image must be a GAR reference pinned by sha256 digest' >&2
  exit 1
fi

workspace="$(cd "$GITHUB_WORKSPACE" && pwd -P)"
root="$(cd "$workspace/$TF_WORKING_DIRECTORY" && pwd -P)"
[[ -d "$root" ]] || { echo 'Terraform root must be a directory' >&2; exit 1; }
case "$root" in
  "$workspace") relative='.' ;;
  "$workspace"/*) relative="${root#"$workspace"/}" ;;
  *) echo 'Terraform root escapes workspace' >&2; exit 1 ;;
esac

# Reports live on the runner, outside the checkout, so the workspace stays clean.
reports_dir="${RUNNER_TEMP}/terraform-security"
mkdir -p "$reports_dir"
echo "report-path=$reports_dir" >> "$GITHUB_OUTPUT"

# Only the checkout and the reports directory are writable in the container.
# No Docker socket, host home directory or GCP credential file is mounted.
docker pull "$TOOLING_IMAGE"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 256 \
  --tmpfs /tmp:rw,nosuid,nodev,size=256m \
  --mount "type=bind,src=$workspace,dst=/workspace" \
  --mount "type=bind,src=$GITHUB_ACTION_PATH/scripts,dst=/platform-scripts,readonly" \
  --mount "type=bind,src=$reports_dir,dst=/reports" \
  --workdir "/workspace/$relative" \
  --env HOME=/tmp \
  --env TF_IN_AUTOMATION=true \
  --env TF_INPUT=0 \
  --env CHECKOV_REPORT_PATH=/reports \
  --entrypoint bash \
  "$TOOLING_IMAGE" /platform-scripts/scan.sh
