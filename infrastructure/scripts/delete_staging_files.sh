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
    delete_version
else
    # If pr number is provided, delete all files associated with the same pr_number
    regex=".*/.*-pr${pr_number}[^0-9]*/${MANIFEST_FILE_NAME}$"
    # Find all manifest files of env versions associated with the pr_number
    # and delete all those versions
    while IFS= read -r manifest_file; do
        delete_version "$manifest_file"
    done < <(
      find "$(dirname "$ENV_DIR")" \
      -type f \
      -regextype posix-extended \
      -regex "$regex"
    )
fi

