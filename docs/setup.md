# GAR, GitHub and pipeline setup

## GCP

1. Enable Artifact Registry, IAM Credentials, Security Token Service and Cloud KMS APIs in the GCP project.
2. Create three Docker-format Artifact Registry repositories in `europe-west2`: `alpha`, `beta` and `live`. Enable immutable tags on all three. Build once into `alpha`, then promote the signed digest to `beta` and `live`.
3. Create a KMS asymmetric signing key for Cosign and grant the publisher service account `roles/cloudkms.signerVerifier` on that key. Grant reader accounts `roles/cloudkms.verifier`.
4. Create dedicated service accounts:
   - `github-tooling-publisher`: `roles/artifactregistry.writer` on the `alpha`/`beta`/`live` repositories only, plus KMS signing.
   - `github-artifact-reader`: `roles/artifactregistry.reader` on the promotion repositories only.
   - `github-terraform-plan`: read-only access to Terraform state and the target resources.
   - `github-terraform-apply` (one per environment): write access to Terraform state and the target resources.
5. Configure Workload Identity Federation for GitHub OIDC, limiting trust to the intended GitHub organization/repository and approved refs. Grant `roles/iam.workloadIdentityUser` on each service account to its restricted WIF principal. Avoid broad `attribute.repository_owner`-only trust; use a separate WIF condition per service account (for example `tooling-publish` for the publisher and `terraform-production` for the apply account).

Repositories are created by plan 0 in `gcp-org-bootstrap`, not by this repo. This repo only publishes into them.

## GitHub variables

Create repository or environment variables:

- `GAR_LOCATION`: `europe-west2`
- `GAR_PROJECT_ID`: your GCP project ID
- `GAR_REPOSITORY_ALPHA`: `alpha` (falls back to the legacy `GAR_REPOSITORY`)
- `GAR_REPOSITORY_BETA`: `beta`
- `GAR_REPOSITORY_LIVE`: `live`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`: full WIF provider resource name
- `GCP_ARTIFACT_WRITER_SA`: publisher service account email
- `GCP_ARTIFACT_READER_SA`: reader service account email
- `GCP_TERRAFORM_PLAN_SA`: plan service account email
- `GCP_TERRAFORM_APPLY_SA`: apply service account email for the target environment
- `COSIGN_KMS_KEY_URI`: full `gcpkms://` key version resource name
- `TERRAFORM_TOOLING_IMAGE`: approved image reference pinned to a digest, e.g. `europe-west2-docker.pkg.dev/<PROJECT>/live/terraform-tooling@sha256:<64 hex>`
- `TF_WORKING_DIRECTORY`: Terraform root relative to the repository root (defaults to `.`)
- `TF_ENABLE_TFLINT`: `true` or `false` (defaults to `true`)

Reusable workflows read the `vars` context of the **calling** repository, so define these variables in every consumer repository (or at organization level).

Create environment `tooling-publish` restricted to `v*` tags, with required reviewers. Protect `main` with CODEOWNERS and required checks, and enable squash merging so PR titles become conventional commit messages. Create an apply environment (default `terraform-production`) with required reviewers and, ideally, a deployment branch policy.

## Workflows

| Workflow | Type | Purpose |
| --- | --- | --- |
| `release-please.yml` | `push` to `main` | Opens/updates a release PR with `CHANGELOG.md` and `VERSION`, then creates the `vX.Y.Z` tag and GitHub release. |
| `conventional-commits.yml` | `pull_request` | Enforces conventional PR titles so SemVer bumps are deterministic. |
| `publish-terraform-tooling.yml` | `push` tag `v*` | Builds, smoke tests, signs, promotes and publishes release evidence. |
| `terraform-pr.yml` | `pull_request` | Runs validation, Checkov and (when configured) image signature checks on PRs to `main`. |
| `terraform-test.yml` | `workflow_call` | Terraform format, init, validate and TFLint in the pinned image. |
| `terraform-security.yml` | `workflow_call` | Checkov scan in the pinned image; uploads a short-lived JSON report. |
| `terraform-image.yml` | `workflow_call` | Verifies the pinned image signature and runs a tool smoke test. |
| `terraform-plan.yml` | `workflow_call` | Creates and uploads a binary plan for a specific commit. |
| `terraform-deploy.yml` | `workflow_call` | Applies that exact saved plan after environment approval. |

All Terraform commands run in the centrally published image. The Docker socket, host home directory and checkout workspace credentials are never mounted into the container; short-lived GCP credentials are mounted from `RUNNER_TEMP` only where plan/apply need them.

## Release process

Releases are driven by conventional commits, not by a manual version input:

1. Merge changes to `main` with PR titles such as `feat(plan): add state bucket module`, `fix(security): correct report guard` or `feat!: change workflow inputs`.
2. `release-please.yml` opens or updates a release PR containing the generated `CHANGELOG.md`, `VERSION` and updated internal workflow refs. This PR is the review gate.
3. Merging the release PR creates tag `vX.Y.Z` and a GitHub release with the changelog.
4. The tag push starts `publish-terraform-tooling.yml`. It builds and signs once in `alpha`, then uses `cosign copy` to promote that exact digest to `beta` and `live` with signatures and attestations intact.
5. The workflow attaches `release-manifest.json` and `VERIFY.md` to the GitHub release. Other repositories consume these as the canonical version, image digest and verification command.

Version bumps: `fix:` → patch, `feat:` → minor, `BREAKING CHANGE:` or `feat!:` → major. Tags and image tags are never reused; re-run the publish workflow on the same tag to recover a failed publish.

### Consuming a release from another repository

Prefer SHA pins with the release in a same-line comment, and let Dependabot update them:

```yaml
- uses: mock-bank/cicd-shared/.github/workflows/terraform-test.yml@<sha> # v1.0.0
```

`release-manifest.json` provides the exact SHA, tag and image digest, and can be used to generate Dependabot PRs or review pin updates. Do not fetch it at CI runtime — that would introduce an unpinned network dependency.

## Publishing the tooling image

Automatic: merge the release PR, then push the tag. The workflow derives the version from the tag, so the version in the release and the OCI label always match. A failed publish can be re-run on the same tag without changing the version.

## Consuming the reusable workflows

A consumer workflow must grant the permissions the called workflow needs. For example:

```yaml
permissions:
  contents: read
  id-token: write # WIF for GAR and, for plan/apply, Google Cloud

jobs:
  test:
    uses: mock-bank/cicd-shared/.github/workflows/terraform-test.yml@<sha> # v1.0.0
    with:
      working-directory: infra
      tooling-image: ${{ vars.TERRAFORM_TOOLING_IMAGE }}

  plan:
    uses: mock-bank/cicd-shared/.github/workflows/terraform-plan.yml@<sha> # v1.0.0
    permissions:
      contents: read
      id-token: write
      actions: write # upload the plan artifact
    with:
      working-directory: infra
      tooling-image: ${{ vars.TERRAFORM_TOOLING_IMAGE }}
      ref: ${{ github.sha }}
```

Pass `needs.plan.outputs.plan-artifact` and `needs.plan.outputs.plan-run-id` to `terraform-deploy.yml`, along with the same `ref` and `working-directory`. The apply job downloads that exact plan, waits for approval in the configured environment, and applies it without `-auto-approve`.

## Pinning standard

Third-party actions are pinned to a full 40-character commit SHA with the release in a same-line comment, for example `actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0`. The older `@v4:<sha>` form is not a valid GitHub ref; `@<sha> # vX.Y.Z` is the form GitHub and Dependabot understand.

Internal workflow and action references use the release tag with an `x-release-please-version` annotation, e.g. `@v1.0.0 # v1.0.0 x-release-please-version`. The annotation lets release-please bump them in the release PR. Consumers should still pin to a SHA using Dependabot.

## Hardening backlog (before bank production adoption)

- Push the initial `v1.0.0` tag so the internal `@v1.0.0` references resolve, then convert them to SHA pins via Dependabot.
- Enable "require actions to be pinned to a full-length commit SHA" in repository/organization settings and add automated dependency updates from the central `mock-bank/dependencies` preset.
- Enforce signed commits and two-person approval on release PRs.
- Verify upstream signed Terraform/TFLint checksums independently during the tooling image build.
- Add container vulnerability gating, runner isolation, organization-wide policies, evidence retention and tool dependency mirroring.
- Revisit BuildKit provenance mode and access controls based on data-classification policy.
- Rotate service accounts and KMS keys on a schedule, and audit WIF conditions and environment approvals.

## Scope

This repository supplies the shared tooling image and the validation, security, plan, approval-gated apply and release workflows. It does not choose resource names, state backends or provider versions for consuming repositories; those remain repository-owned through committed Terraform configuration and lock files.
