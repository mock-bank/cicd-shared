FROM python:3.15-slim-bookworm@sha256:96599df822d0e1c6bb700014a05c7f3c8cabc6e0f7ff3c4f9f69cee033b4b5d9

ARG TARGETARCH
ARG TERRAFORM_VERSION=1.17.2
ARG TFLINT_VERSION=0.64.0
ARG CHECKOV_VERSION=3.3.21

## Setting environment variables
# DEBIAN_FRONTEND - Prevents interactive prompts during package installation.
# PIP_DISABLE_PIP_VERSION_CHECK - Disables pip version check to speed up installations.
# TF_IN_AUTOMATION - Indicates that Terraform is running in an automated environment, suppressing certain prompts.
# TF_INPUT - Disables interactive input prompts for Terraform commands.
# PATH - Adds the Checkov virtual environment's bin directory to the system PATH, allowing Checkov to be run from anywhere in the container.
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    TF_IN_AUTOMATION=true \
    TF_INPUT=0 \
    PATH="/opt/checkov-venv/bin:${PATH}"

## Installing system dependencies
# ca-certificates - Ensures that the container can establish secure HTTPS connections.
# curl - A command-line tool for transferring data with URLs, used for downloading files and making HTTP requests.
# git - A version control system for tracking changes in source code, useful for cloning repositories.
# jq - A lightweight and flexible command-line JSON processor, useful for parsing and manipulating JSON data.
# unzip - A utility for extracting compressed files, often used for unpacking downloaded archives.
# openssh-client - Provides SSH client capabilities, allowing the container to connect to remote servers via SSH.
# rm -rf /var/lib/apt/lists/* - Cleans up the package lists after installation to reduce the image size and remove unnecessary files.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git jq unzip openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Validate against the checksum files published with official releases.
# An independent signed-checksum verification step is recommended for production.
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in amd64|arm64) arch="${TARGETARCH:-amd64}" ;; *) exit 1 ;; esac; \
    curl -fsSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"; \
    curl -fsSLo /tmp/terraform_SHA256SUMS "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    grep " terraform_${TERRAFORM_VERSION}_linux_${arch}.zip$" /tmp/terraform_SHA256SUMS | sed "s#terraform_${TERRAFORM_VERSION}_linux_${arch}.zip#/tmp/terraform.zip#" | sha256sum -c -; \
    unzip -q /tmp/terraform.zip -d /usr/local/bin; \
    rm -f /tmp/terraform.zip /tmp/terraform_SHA256SUMS; \
    terraform version

RUN set -eux; \
    case "${TARGETARCH:-amd64}" in amd64|arm64) arch="${TARGETARCH:-amd64}" ;; *) exit 1 ;; esac; \
    curl -fsSLo /tmp/tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${arch}.zip"; \
    curl -fsSLo /tmp/tflint_checksums.txt "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/checksums.txt"; \
    grep " tflint_linux_${arch}.zip$" /tmp/tflint_checksums.txt | sed "s#tflint_linux_${arch}.zip#/tmp/tflint.zip#" | sha256sum -c -; \
    unzip -q /tmp/tflint.zip -d /usr/local/bin; \
    rm -f /tmp/tflint.zip /tmp/tflint_checksums.txt; \
    tflint --version

RUN python -m venv /opt/checkov-venv \
    && /opt/checkov-venv/bin/pip install --no-cache-dir "checkov==${CHECKOV_VERSION}" \
    && checkov --version

WORKDIR /workspace
CMD ["bash"]