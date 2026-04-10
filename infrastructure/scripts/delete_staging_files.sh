#!/usr/bin/env bash

# This script is used to delete the staging files associated to a Pull Request or
# production environment deployment.

# Usage: delete_staging_files.sh [<pr_number>]

# There are two deletion cases:
# 1. PRODUCTION env deployed through a workflow dispatch.
#    In this case, there is only one staging environment deployed and it can be identified through
#    the $MODULE_VERSION variable.
# 2. STAGING envs deployment within a Pull Request.
#    In this case, there can be multiple environments deployed within the same PR.
#    All these environments can be identified with the <pr_number> positional parameter.

set -euo pipefail

if [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == "1" ]]; then
    set -x
fi

pr_number="${1:-}"

# Set configuration env variables
source "$CONFIG"

# Delete module files
if [[ -z "$pr_number" ]]; then
    # If no pr number is provided, only delete the files associated with the current version
    echo "Deleting STAGING files associated to version '$MODULE_VERSION':"
    delete_files_in_manifest
else
    # If pr number is provided, delete all files associated with that pr_number
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

