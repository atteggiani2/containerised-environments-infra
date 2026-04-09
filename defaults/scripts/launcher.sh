#!/usr/bin/env bash

# The double underscore variables within this file are replaced by the 'replace_dunder_variables'
# function within the build.sh or deploy.sh scripts

# To print debug messages, set the DEBUG env var to 1.
[[ -n "${DEBUG+x}" ]] && set -x
# Immediately exit if any command fails
set -e

### Add some complicated arguments that are never meant to be used by humans
# declare -a PROG_ARGS=()
# while [[ $# -gt 0 ]]; do
#     case "${1}" in 
#         "--cms_singularity_overlay_path_override")
#             ### Sometimes we do not want to use the 'correct' container
#             export CONTAINER_OVERLAY_PATH_OVERRIDE=1
#             debug_echo "cms_singularity_overlay_path_override=1"
#             shift
#             ;;
#         "--cms_singularity_overlay_path")
#             ### From time to time we need to manually specify an overlay filesystem, handle that here:
#             export ADDITIONAL_CONTAINER_OVERLAYS="${2}"
#             debug_echo "cms_singularity_overlay_path="${ADDITIONAL_CONTAINER_OVERLAYS}
#             shift 2
#             ;;
#         "--cms_singularity_in_container_path")
#             ### Set path manually
#             export PATH="${2}"
#             debug_echo "cms_singularity_in_container_path="${PATH}
#             shift 2
#             ;;
#         "--cms_singularity_launcher_override")
#             ### Override the launcher script name
#             export LAUNCHER_SCRIPT="${2}"
#             debug_echo "cms_singularity_launcher_override="${LAUNCHER_SCRIPT}
#             shift 2
#             ;;
#         "--cms_singularity_singularity_path")
#             export SINGULARITY_BINARY_PATH="${2}"
#             $debug "cms_singularity_singularity_path="${SINGULARITY_BINARY_PATH}
#             shift 2
#             ;;
#         *)
#             PROG_ARGS+=( "${1}" )
#             shift
#             ;;
#     esac
# done

# name of the original launcher script
original_launcher_script_name='__LAUNCHER_SCRIPT_NAME__'

### Get commands for the container
# If this launcher script was run explicitely (e.g., `__LAUNCHER_SCRIPT_NAME__ mycommand --option`), 
# then the commands to run within the container are only the arguments after the launcher
# (`mycommand --option`), so we omit $0.
# If instead it was run from a symlink (e.g., `python3 mycommand --option`), 
# then the commands to run within the container are the full arguments including the symlink name
# (`python3 mycommand --option`), so we include $0.

CMD="$0"
if [ "$(basename "$CMD")" == "$original_launcher_script_name" ]; then
    CMD="$1"
    if [ $# -gt 0 ]; then
        shift
    fi
fi

# If this script gets run within the container,  we should not call another 
# singularity container, but only run the command:
if [ -n "$SINGULARITY_CONTAINER" ]; then
    exec -a "$CMD" "$(basename "$CMD")" "$@"
fi

# Path of the container image
container_image_path='__RUNTIME_CONTAINER_IMAGE_PATH__'

# Directories from the host to bind to the container
bind_str='__BIND_STR__'

# Path to the squashfs file with the overlay environment
squashfs_file='__SQSH_FILE_PATH__'

# Keep LD_LIBRARY_PATH from the host within the container
export SINGULARITYENV_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"

# Set overlays to use within the container
# Get the additional overlays
IFS=',' read -ra container_overlays <<< '__ADDITIONAL_CONTAINER_OVERLAYS__'
# Create overlay arguments for singularity exec command
for overlay_path in "${container_overlays[@]}"; do
    overlay_str+="--overlay=${overlay_path} "
done
# Add current environment's sqsh as the last overlay so it has priority over the other overlays
overlay_str+="--overlay=${squashfs_file}"


# Set PYTHONNOUSERSITE inside the container
export SINGULARITYENV_PYTHONNOUSERSITE='__PYTHONNOUSERSITE__'

# Disable Python's bytecode cache (.pyc files) inside the container
export SINGULARITYENV_PYTHONDONTWRITEBYTECODE='__PYTHONDONTWRITEBYTECODE__'

# Set path to the environment activation script within the container
export SINGULARITYENV_ENV_ACTIVATION_SCRIPT='__ACTIVATION_SCRIPT_PATH__'

function singularity_exec () {
    exec singularity -s run \
      --bind "$bind_str" \
      "$overlay_str" \
      "$container_image_path" \
      "$CMD" "$@"
}

# Use latest singularity if needed
if ! command -v singularity &> /dev/null; then
    singularity_exe='__SINGULARITY_EXE__'
    echo "Singularity could not be found, using latest singularity executable: $singularity_exe"
    singularity_dir=$( dirname "$singularity_exe" )
    export PATH="$singularity_dir:$PATH"
fi

singularity_exec "$@"
exit $?