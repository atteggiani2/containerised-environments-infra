#!/usr/bin/env bash

#PBS -q copyq
#PBS -l ncpus=1
#PBS -l walltime=2:00:00
#PBS -l mem=20GB
#PBS -l jobfs=50GB
#PBS -W umask=0037

set -euo pipefail
if [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Redirect STDOUT and STDERR of this shell to the PBS job log file, to 
# be able to capture all STDOUT and STDERR of the PBS job without having to wait
# for the job to end
exec &> "$PBS_JOB_LOG_FILE"

# Set configuration env variables
source "$CONFIG"

### Initialise directories
# Make sure the target environment directory does not already exist, to avoid accidentally overwriting an existing environment.
if [[ -d "$ENV_DIR" ]]; then
    echo "Error! Environment version '$MODULE_NAME/$MODULE_VERSION' already exists." >&2
    exit 1
fi
# Create a trap function that would delete the environment version related files
# in case the script fails
cleanup_env() {
    # _exit_status is initialised within the trap_append function
    if [ $_exit_status -ne 0 ]; then
        echo "Error! Build failed. Cleaning up environment version '$MODULE_NAME/$MODULE_VERSION' related files..." >&2
        delete_version
    fi
}
trap_append cleanup_env EXIT

echo 'Initialising directories...'
mkdir -pv "$ENV_DIR"
mkdir -pv "$MODULE_DIR"
mkdir -pv "$ENV_BIN_DIR"
mkdir -pv "$(dirname "$TEMP_ENV_DIR")"


### CREATE HPC TARGET DEPLOYMENT INFO JSON
# Set a trap function to update the HPC target deployment info JSON when the script exits
update_hpc_target_deployment_info() {
    # _exit_status is initialised within the trap_append function
    export SUCCESS=$( [ $_exit_status -eq 0 ] && echo true || echo false )
    # Update the HPC target deployment info JSON
    source "$INFRA_SCRIPTS_DIR/create_hpc_target_deployment_info_json.sh" "$HPC_TARGET_DEPLOYMENT_INFO_JSON_PATH"
}
trap_append update_hpc_target_deployment_info EXIT


### CREATE MANIFEST FILE
# Create a manifest file listing all the files and folders related to the current environment version:
# - Modulefile
# - Env activation file
# - Env folder

cat > "$MANIFEST_FILE_PATH" <<EOF
$MODULE_FILE_PATH
$ACTIVATION_SCRIPT_PATH
$ENV_DIR
EOF

### UPDATE CONTAINER IMAGE
container_image=$(
    get_overrides_or_defaults "$REPO_CONTAINER_IMAGE_PATH" \
    "No container image '${REPO_CONTAINER_IMAGE_PATH#$DEFAULTS_DIR/}' found in the repository's defaults or environment overrides.
    To create it, run the 'build_container_image.yml' repository workflow."
)
copy_if_changed "$container_image" "$RUNTIME_CONTAINER_IMAGE_PATH"
echo "Container image deployed to '$RUNTIME_CONTAINER_IMAGE_PATH'"

### CREATE ENVIRONMENT
echo 'Creating environment within the container...'

# Even though we create the environment in a host working directory, we build the Python environment within the container
# so it's safer for everything to be working as expected once the environment runs within the container itself

# To make sure the paths needed within the container for the environment creation 
# are bound to the host paths, they need to be added to the BIND_STR. 
# This might not be necessary on Gadi, as its singularity configuration automatically 
# binds '/g' and '/scratch' folders, but we add them here anyway for safety.
# We also make sure to bind the temporary directory on the host where the environment
# is created, to the target internal directory where the overlay environment
# will reside (using <host_bound_dir>:<internal_dir>). This ensures that the
# environment is built at the same path it will have at runtime, so the
# squashfs overlay functions correctly.

add_to_bind=(
    "$MAMBA_EXE"
    "$ENV_FILE"
    "$(dirname "$TEMP_ENV_DIR"):$(dirname "$INTERNAL_ENV_DIR")"
)
# Use printf %q for safety with bash special characters like spaces.
add_bind_str=$(printf ",%q" "${add_to_bind[@]}")

# Initialise singularity
module load -v singularity

singularity -s exec \
    --bind "${BIND_STR}${add_bind_str}" \
    "$RUNTIME_CONTAINER_IMAGE_PATH" \
    bash <<EOF

set -euo pipefail
if [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Print environment specification for debugging purposes
echo 'Creating environment using the following environment specification:'
cat "$ENV_FILE"
echo ''   # ensure newline after cat output

# Create the environment
# We use --no-rc to disable the use of configuration files
# We use --no-env to disable the use of environment variables
# We use --root-prefix to specify the cache packages dir, to avoid parallel 
# env creation failing because mircomamba tries to access the cache at the same time
"$MAMBA_EXE" create -y \
    --prefix "$INTERNAL_ENV_DIR" \
    --file "$ENV_FILE" \
    --no-rc \
    --no-env \
    --root-prefix "$TEMP_WORKING_DIR"

# Clear the cache to save space
"$MAMBA_EXE" clean -afy

EOF

### CREATE SQUASHFS OVERLAY
echo 'Creating squashfs overlay...'

# The first argument to `mksquashfs` must be the full path to the environment,
# truncated at the directory level that should appear as a subdirectory of the
# container’s root (`/`). We also use `-keep-as-directory` to preserve the final
# directory and ensure the environment ends up at the correct path inside the container
# when the squashfs file is overlaid.
# E.g., if the environment exists at:
# /path/to/current/temp/env/version
# and it should appear inside the container as:
# /temp/env/version
# then `mksquashfs` must be invoked as:
# mksquashfs /path/to/current/temp ... -keep-as-directory

# Get truncated env path (first argument to mksquashfs command)
first_internal_path_portion="${INTERNAL_ENV_DIR#/}"
first_internal_path_portion="${first_internal_path_portion%%/*}"
env_path_truncated="$TEMP_WORKING_DIR/$first_internal_path_portion"

# Set permissions within the squashfs
set_perms "$env_path_truncated"

# Pack the environment into squashfs
mksquashfs "$env_path_truncated" "$TEMP_SQSH_FILE_PATH" \
    -keep-as-directory -no-fragments -no-duplicates -no-sparse \
    -no-exports -no-recovery -no-xattrs -noD -noI -processors 8

# Deploy the squashfs file and set permissions
copy_if_changed "$TEMP_SQSH_FILE_PATH" "$SQSH_FILE_PATH"
set_perms "$SQSH_FILE_PATH"
echo "Squashfs file deployed to '$SQSH_FILE_PATH'"

### DEPLOY MODULE FILES
echo 'Creating module files...'

# Modulefile
modulefile=$(
    get_overrides_or_defaults "$REPO_MODULE_FILE_PATH" \
    "No modulefile '${REPO_MODULE_FILE_PATH#$DEFAULTS_DIR/}' found in the repository's defaults or environment overrides."
)
# .modulerc
modulerc=$(
    get_overrides_or_defaults "$REPO_MODULERC_FILE_PATH" \
    "No .modulerc file '${REPO_MODULERC_FILE_PATH#$DEFAULTS_DIR/}' found in the repository's defaults or environment overrides."
)
# Environment activation script
env_activation_script=$(
    get_overrides_or_defaults "$REPO_ACTIVATION_SCRIPT_PATH" \
    "No environment activation script '${REPO_ACTIVATION_SCRIPT_PATH#$DEFAULTS_DIR/}' found in the repository's defaults or environment overrides."
)

# Deploy module-related files and set permissions
copy_if_changed_with_replace "$env_activation_script" "$ACTIVATION_SCRIPT_PATH"
set_perms "$ACTIVATION_SCRIPT_PATH"
echo "Environment activation script deployed to '$ACTIVATION_SCRIPT_PATH'"

copy_if_changed_with_replace "$modulefile" "$MODULE_FILE_PATH"
set_perms "$MODULE_FILE_PATH"
echo "Module file deployed to '$MODULE_FILE_PATH'"

copy_if_changed_with_replace "$modulerc" "$MODULERC_FILE_PATH"
set_perms "$MODULERC_FILE_PATH"
echo "Module .modulerc file deployed to '$MODULERC_FILE_PATH'"


### COPY LAUNCHER SCRIPT AND LINK BINARIES
# Launcher script
launcher_script=$(
    get_overrides_or_defaults "$REPO_LAUNCHER_SCRIPT_PATH" \
    "No launcher script '${REPO_LAUNCHER_SCRIPT_PATH#$DEFAULTS_DIR/}' found in the repository's defaults or environment overrides."
)

# Deploy launcher script and set permissions
copy_if_changed_with_replace "$launcher_script" "$LAUNCHER_SCRIPT_PATH"
# Add execute permissions to the launcher script
chmod u+x "$LAUNCHER_SCRIPT_PATH"
set_perms "$LAUNCHER_SCRIPT_PATH"
echo "Launcher script deployed to '$LAUNCHER_SCRIPT_PATH'"

# Create symlinks to the launcher script for all binaries in the environment,
# with exception of those in HOST_EXECUTABLES (that will not be linked)
IFS=',' read -ra host_executables <<< "$HOST_EXECUTABLES"
for binfile in "$TEMP_ENV_DIR"/bin/*; do
    binfile_name=$(basename "$binfile")
    if ! in_array "$binfile_name" "${host_executables[@]}"; then
        ln -s "$LAUNCHER_SCRIPT_PATH" "$ENV_BIN_DIR/$binfile_name"
    fi
done
echo "Environment binaries linked to launcher script"

### GENERATE ENVIRONMENT LOCK
source "$INFRA_SCRIPTS_DIR/generate_env_lock.sh" > "$ENV_LOCK_FILE_PATH"
echo "Environment lock created to: '$ENV_LOCK_FILE_PATH'"

### CLEANUP OLDEST DEVELOPMENT ENV FOR PRODUCTION
source "$INFRA_SCRIPTS_DIR/cleanup_old_dev_env.sh"

### EXPORT ENV VARIABLES FOR HPC TARGET DEPLOYMENT INFO JSON
# MODULE_USAGE_INSTRUCTIONS
export MODULE_USAGE_INSTRUCTIONS="module use $ALL_MODULES_DIR
module load $MODULE_NAME/$MODULE_VERSION"
# ENV_LOCK
export ENV_LOCK=$(cat "$ENV_LOCK_FILE_PATH")