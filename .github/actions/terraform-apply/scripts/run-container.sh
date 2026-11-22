#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_WORKSPACE:?Missing GitHub workspace}"
: "${GITHUB_ACTION_PATH:?Missing composite action path}"
: "${RUNNER_TEMP:?Missing GitHub runner temp directory}"
: "${TOOLING_IMAGE:?Missing tooling image}"
: "${TF_WORKING_DIRECTORY:?Missing Terraform directory}"
: "${TF_PLAN_PATH:?Missing Terraform plan file}"

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

plan_path="$(cd "$(dirname "$TF_PLAN_PATH")" && pwd -P)/$(basename "$TF_PLAN_PATH")"
case "$plan_path" in
  "$RUNNER_TEMP"/*) ;;
  *) echo 'Plan file must be stored in the runner temp directory' >&2; exit 1 ;;
esac
plan_dir="$(dirname "$plan_path")"
plan_name="$(basename "$plan_path")"

docker_args=(
  --rm
  --user "$(id -u):$(id -g)"
  --cap-drop ALL
  --security-opt no-new-privileges
  --pids-limit 256
  --tmpfs /tmp:rw,nosuid,nodev,size=256m
  --mount "type=bind,src=$workspace,dst=/workspace"
  --mount "type=bind,src=$GITHUB_ACTION_PATH/scripts,dst=/platform-scripts,readonly"
  --mount "type=bind,src=$plan_dir,dst=/plan,readonly"
  --workdir "/workspace/$relative"
  --env HOME=/tmp
  --env TF_IN_AUTOMATION=true
  --env TF_INPUT=0
  --env TF_PLAN_PATH="/plan/$plan_name"
)

# google-github-actions/auth writes short-lived credentials under RUNNER_TEMP.
# Mount that file into the container and never into the checkout workspace.
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  creds="$(cd "$(dirname "$GOOGLE_APPLICATION_CREDENTIALS")" && pwd -P)/$(basename "$GOOGLE_APPLICATION_CREDENTIALS")"
  case "$creds" in
    "$RUNNER_TEMP"/*) ;;
    *) echo 'GCP credentials must be stored in the runner temp directory' >&2; exit 1 ;;
  esac
  docker_args+=(
    --mount "type=bind,src=$creds,dst=/tmp/gcp-creds.json,readonly"
    --env GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp-creds.json
  )
fi

for var in GOOGLE_CLOUD_PROJECT GOOGLE_REGION; do
  if [[ -n "${!var:-}" ]]; then
    docker_args+=(--env "$var=${!var}")
  fi
done

docker pull "$TOOLING_IMAGE"
docker run "${docker_args[@]}" \
  --entrypoint bash \
  "$TOOLING_IMAGE" /platform-scripts/apply.sh
