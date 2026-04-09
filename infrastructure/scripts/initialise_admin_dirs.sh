#!/usr/bin/env bash

# Script to create the admin directory and subdirectories on HPC and set the right permissions

set -euo pipefail
if [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == "1" ]]; then
    set -x
fi

function set_admin_perms() {
    # Set admin permissions for each of the provided arguments
    local arg
    for arg in "$@"; do
        if [[ -L "${arg}" ]]; then # Links
            # Change group ownership for the link (not the file it points to)
            chgrp -h "${GROUP_OWNER}" "${arg}"
        elif [[ -d "${arg}" ]]; then # Directories
            # Change group ownership recursively
            chgrp -R "${GROUP_OWNER}" "${arg}"
            # Set group permissions recursively to match user permissions
            # and remove all permissions for others
            chmod -R g=u,o= "${arg}"
            # Set group ID bit, to have all children files and directories inherit the directory's group
            chmod g+s "${arg}"
            # Set specific permissions to OWNER recursively to read, write and execute 
            # (only if someone else already has execute) permissions, also for new files and directories.
            # Remove all permissions for the group, to ensure only the owner has access to the admin directories and files
            setfacl -R -m g:"${GROUP_OWNER}":---,u:"${OWNER}":rwX,d:g:"${GROUP_OWNER}":---,d:u:"${OWNER}":rwX "${arg}"
        elif [[ -f "${arg}" ]]; then # Files
            ### reset any existing acls
            setfacl -b "${arg}"
            # Change group ownership
            chgrp "${GROUP_OWNER}" "${arg}"
            # Set group permissions to match user permissions
            # and remove all permissions for others
            chmod g=u,o= "${arg}"
            # Set specific permissions to OWNER to read, write and execute 
            # (only if someone else already has execute) permissions
            # Remove all permissions for the group, to ensure only the owner has access to the admin directories and files
            setfacl -m g:"${GROUP_OWNER}":---,u:"${OWNER}":rwX "${arg}"
        fi
    done
}

directories=(
    "$STABLE_PRODUCTION_BASE_DIR"
    "$ADMIN_DIR"
    "$LOGS_DIR"
)

for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    set_admin_perms "$dir"
done