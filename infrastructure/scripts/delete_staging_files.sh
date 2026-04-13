#!/usr/bin/env bash

# This script is used to delete the staging files associated to a STAGING environment deployment.

# Usage: delete_staging_files.sh [<pr_number> | --all]

# There are three deletion cases:
# 1. PRODUCTION env deployed through a workflow dispatch.
#    In this case, there is only one staging environment deployed and it can be identified through
#    the $MODULE_VERSION variable (this script doesn't need any additional parameters).
# 2. STAGING envs deployment within a Pull Request.
#    In this case, there can be multiple environments deployed within the same PR
#    (this script needs the pr_number positional parameter to identify all the environments associated with that PR).
# 3. All STAGING envs deployment.
#    In this case, all files in the staging directories (STABLE and DEVELOPMENT) will be deleted.
#    (this script needs the --all flag).

set -euo pipefail

if [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Sanity check on the input parameters
if [[ "$#" -gt 1 ]]; then
    echo "Error: too many parameters."
    exit 1
elif [[ ${1:-} != '--all' && ! ${1:-0} =~ ^[0-9]+$ ]]; then
    echo "Error: invalid parameter. Please provide either a PR number or the '--all' flag."
    exit 1
fi

# Set configuration env variables
source "$CONFIG"

# Delete module files
if [[ -z "${1:-}" ]]; then
    # No arguments are provided: only delete the files associated with the current version
    echo "Deleting STAGING files associated to version '$MODULE_VERSION':"
    delete_files_in_manifest
elif [[ "${1:-}" == '--all' ]]; then
    # If --all flag is provided, delete all files in the staging directories
    # We perform an extra check to avoid runing the rm command with empty variables
    if [[ -z "$STABLE_STAGING_BASE_DIR" ]]; then
        echo "Error: STABLE_STAGING_BASE_DIR is empty"
        exit 1
    elif [[ -z "$DEVELOPMENT_STAGING_BASE_DIR" ]]; then
        echo "Error: DEVELOPMENT_STAGING_BASE_DIR is empty"
        exit 1
    else
        rm -rf "$STABLE_STAGING_BASE_DIR"/* "$DEVELOPMENT_STAGING_BASE_DIR"/*
    fi
else
    pr_number="$1"
    # Pr number is provided: delete all files associated with that pr_number
    # Define regex to find all manifests of env versions associated with the pr_number
    regex=".*/.*-pr${pr_number}[^0-9]*/${MANIFEST_FILE_NAME}$"
    # We need to find both DEVELOPMENT and STABLE environments.
    # The DEVELOPMENT environment directory is ENV_DIR (because we run this within a workflow without
    # is_stable and its default value is false)
    # The STABLE environment directory is derived from ENV_DIR by removing the DEVELOPMENT_STAGING_BASE_DIR
    # prefix and adding the STABLE_STAGING_BASE_DIR prefix instead.
    development_env_dir="$ENV_DIR"
    stable_env_dir="$STABLE_STAGING_BASE_DIR/${ENV_DIR#$DEVELOPMENT_STAGING_BASE_DIR/}"
    # Only add directories if they exist, otherwise the find command below would fail
    dirs=()
    if [[ -d "$development_env_dir" ]]; then
      dirs+=("$development_env_dir")
    fi
    if [[ -d "$stable_env_dir" ]]; then
      dirs+=("$stable_env_dir")
    fi
    # Find all manifest files of env versions associated with the pr_number and delete all the related files
    while IFS= read -r manifest_file; do
        delete_files_in_manifest "$manifest_file"
    done < <(
      find "${dirs[@]}" \
      -type f \
      -regextype posix-extended \
      -regex "$regex"
    )
fi

