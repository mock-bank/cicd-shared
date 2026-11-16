# Initial GAR and GitHub setup

## GCP
1. Enable Artifact Registry, IAM Credentials, and Security Token Service APIs in the GCP project.
2. Create a Docker-format Artifact Registry repository, e.g. `ci-images`, in `europe-west2`.
3. Create a dedicated service account, e.g. `github-tooling-publisher`.
4. Grant that service account `roles/artifactregistry.writer` on **only** the `ci-images` repository.
5. Configure Workload Identity Federation for GitHub OIDC, limiting trust to the intended GitHub organization/repository and approved `main` branch or protected `tooling-publish` environment. Grant `roles/iam.workloadIdentityUser` on the service account to the restricted WIF principal. Avoid broad `attribute.repository_owner`-only trust.

## GitHub
Create repository or environment variables:
- `GAR_LOCATION`: `europe-west2`
- `GAR_PROJECT_ID`: your GCP project ID
- `GAR_REPOSITORY`: `ci-images`
- `GCP_WORKLOAD_IDENTITY_PROVIDER`: full WIF provider resource name
- `GCP_ARTIFACT_WRITER_SA`: service account email

Create environment `tooling-publish` restricted to `main`, with required reviewers. Protect `main` with CODEOWNERS and required checks.

In Actions, run **Publish Terraform Tooling to GAR** via `workflow_dispatch` from `main` with `version=0.1.0`.

Expected artifact: `europe-west2-docker.pkg.dev/<PROJECT>/ci-images/terraform-tooling:0.1.0`.
Use the digest printed in the workflow summary for consumption.

## Hardening backlog (before bank production adoption)
- Replace third-party action version tags with reviewed full commit SHAs.
- Pin the Python base image by digest; verify upstream signed Terraform/TFLint checksums independently.
- Ensure each tag is never overwritten (GAR immutable tags / release governance).
- Add container vulnerability gating and image signing/verification.
- Add approval tests, runner isolation, organization-wide policies, evidence retention and tool dependency mirroring.
- Revisit BuildKit provenance mode and access controls based on data-classification policy.

## Scope
This is increment 1 only: **tooling image and GAR publishing**. It does not run Terraform on customer code, generate plans, or deploy infrastructure. No deployment image is built in this step.
