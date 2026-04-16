# !!! INFORMATION FOR DEVELOPERS !!!
# Sourced by 'infrastructure/scripts/build_and_deploy_env.sh' to configure the
# build and deployment of the containerised environment.

# Some of the variables in this script can be overridden for a specific environment using the
# 'environments/<env_name>/overrides/scripts/config.sh' file.
#
# Overridable variables:
# - INTERNAL_ENV_DIR --> Absolute path (must start with '/') where the environment will be located within the container
# - MAMBA_INSTALLATION_DIR --> Directory where the micromamba executable is found (or installed), if no custom MAMBA_EXE is set
# - MAMBA_EXE --> Executable used to manage conda environments
# - ENV_PROMPT_MODIFIER --> The modifier that can be used to change the PS1 prompt after the environment is activated
# - JQ_EXE --> Executable used to manage JSON files
# - PYTHONNOUSERSITE --> Default set to true. Set to false to include user local Python packages in the Python environment
# - PYTHONDONTWRITEBYTECODE --> Default set to 1. Set to 0 to allow Python to write bytecode cache (.pyc files)
# - HOST_EXECUTABLES --> Comma-separated list of executables not to be symlinked to the launcher script.
#                        These executables will always run on the host and not inside the container,
#                        even if they are present in the environment's bin directory.
# - ADDITIONAL_CONTAINER_OVERLAYS --> Comma-separated list of additional paths to squashfs environments to overlay
#                                     to the container at runtime, and therefore make available within
#                                     the container.


set -euo pipefail
if [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == 1 ]]; then
    set -x
fi

# Set the default DEPLOYMENT_STAGE
DEPLOYMENT_STAGE=${DEPLOYMENT_STAGE:-}

# Sanity check on ENV_TYPE
if [[ "$ENV_TYPE" != STABLE && "$ENV_TYPE" != DEVELOPMENT ]]; then
    echo "Error: Invalid ENV_TYPE '$ENV_TYPE'. Must be either 'STABLE' or 'DEVELOPMENT'." >&2
    exit 1
fi

# Path to the repository functions script
export functions="$INFRA_SCRIPTS_DIR/functions.sh"
if [ ! -f "$functions" ]; then
    echo "Error! Functions file '${functions#$REPO_PATH/}' not found in the repository!" >&2
    exit 1
fi
# Make functions available
source "$functions"

# Set BASE_DIR depending on the deployment stage and environment type:
# - STABLE environment for PRODUCTION --> $STABLE_PRODUCTION_BASE_DIR
# - STABLE environment for STAGING --> $STABLE_STAGING_BASE_DIR
# - DEVELOPMENT environment for PRODUCTION --> $DEVELOPMENT_PRODUCTION_BASE_DIR
# - DEVELOPMENT environment for STAGING --> $DEVELOPMENT_STAGING_BASE_DIR

if [[ "$ENV_TYPE" == DEVELOPMENT ]]; then
    if [[ "$DEPLOYMENT_STAGE" == PRODUCTION ]]; then
        # DEVELOPMENT environment deployed to PRODUCTION
        BASE_DIR="$DEVELOPMENT_PRODUCTION_BASE_DIR"
    else
        # DEVELOPMENT environment deployed to STAGING 
        # Or cases where no deployment takes place (e.g., staging files deletion)
        BASE_DIR="$DEVELOPMENT_STAGING_BASE_DIR"
    fi
elif [[ "$DEPLOYMENT_STAGE" == PRODUCTION ]]; then
    # STABLE environment deployed to PRODUCTION
    BASE_DIR="$STABLE_PRODUCTION_BASE_DIR"
else
    # STABLE environment deployed to STAGING
    # Or cases where no deployment takes place (e.g., staging files deletion)
    BASE_DIR="$STABLE_STAGING_BASE_DIR"
fi

### Export variables needed also when no deployment takes place (e.g., staging files deletion)
# Name of the subdirectory where all apps will be stored
export APPS_DIR="$BASE_DIR/$APPS_DIR_NAME"
# Full path of the directory where the containerised environments infrastructure
# is stored. It usually contains the executable used for environment
# management/creation, as well as configuration and files for each different 
# existing environment
containerised_envs_root_dir="$APPS_DIR/$CONTAINERISED_ENVS_ROOT_DIR_NAME"
# Path to the directory containing all versions of the containerised environment
export ENV_DIR="$containerised_envs_root_dir/envs/$MODULE_NAME"
# Path to the directory containing the containerised environment specific version
export ENV_VERSION_DIR="$ENV_DIR/$MODULE_VERSION"
# Manifest file name for easy env version deletion
export MANIFEST_FILE_NAME=manifest.txt
# Manifest file for easy env version deletion
export MANIFEST_FILE_PATH="$ENV_VERSION_DIR/$MANIFEST_FILE_NAME"

### Logic that runs only if a deployment is taking place
if [[ "$DEPLOYMENT_STAGE" == PRODUCTION ]] || [[ "$DEPLOYMENT_STAGE" == STAGING ]]; then
    # Create base directory if not present
    mkdir -pv "$BASE_DIR"

    # Path to the repository environment directory
    env_folder="$REPO_PATH/environments/$MODULE_NAME"
    # Path to the repository environment overrides directory
    export ENV_OVERRIDES_DIR="$env_folder/overrides"

    # Source the specific environment configuration
    env_config_file="${CONFIG/#$DEFAULTS_DIR/$ENV_OVERRIDES_DIR}"
    [[ -f "$env_config_file"  ]] && source "$env_config_file"

    # Temporary working directory to build the Python environment
    export TEMP_WORKING_DIR="$(mktemp -d)"
    # Clean up temporary directory on exit, but preserve it if there was an error and debugging is enabled
    temp_dir_cleanup() {
        # _exit_status is initialised within the trap_append function
        if [ $_exit_status -eq 0 ] && [[ "${CONTAINERISED_ENVS_DEBUG:-0}" == 1 ]]; then
            echo "Cleaning up temporary directory '$TEMP_WORKING_DIR'"
            rm -rf "$TEMP_WORKING_DIR"
        fi
    }
    trap_append temp_dir_cleanup EXIT

    # Absolute path where the environment will be located within the container
    # This path is added as an overlay when overlaying the squashfs to the container
    export INTERNAL_ENV_DIR=${INTERNAL_ENV_DIR:-"/$CONTAINERISED_ENVS_ROOT_DIR_NAME/$MODULE_NAME/$MODULE_VERSION"}
    # Sanity check on INTERNAL_ENV_DIR being an absolute path
    if [[ "$INTERNAL_ENV_DIR" != /* ]]; then
        echo "INTERNAL_ENV_DIR must be an absolute path (must start with a forward slash). Got '$INTERNAL_ENV_DIR'" >&2
    fi
    # Absolute path where the environment binaries will be located within the container
    export INTERNAL_ENV_BIN_DIR="$INTERNAL_ENV_DIR/bin"

    # Temporary directory where the environment is created
    export TEMP_ENV_DIR="${TEMP_WORKING_DIR}${INTERNAL_ENV_DIR}"

    # Full path of the directory where all module files will be stored
    export ALL_MODULES_DIR="$BASE_DIR/$MODULES_DIR_NAME"
    # Full path of the directory where the specific module will be stored
    export MODULE_DIR="$ALL_MODULES_DIR/$MODULE_NAME"
    # Full path of the modulefile
    export MODULE_FILE_PATH="$MODULE_DIR/$MODULE_VERSION"
    # Full path of the .modulerc file
    export MODULERC_FILE_PATH="$MODULE_DIR/.modulerc"
    # Name of the environment activation script that gets run when users load the module
    activation_script_name=".${MODULE_VERSION}_activate"
    # Path of the environment activation script that gets run when users load the module
    export ACTIVATION_SCRIPT_PATH="$MODULE_DIR/$activation_script_name"
    # Path of the default environment activation script within the repository
    export REPO_ACTIVATION_SCRIPT_PATH="$SCRIPTS_DIR/env_activation.sh"
    # Path to the default modules directory within the repository
    export REPO_MODULES_DIR="$DEFAULTS_DIR/modules"
    # Path to the default modulefile within the repository
    export REPO_MODULE_FILE_PATH="$REPO_MODULES_DIR/modulefile"
    # Path to the default .modulerc file within the repository
    export REPO_MODULERC_FILE_PATH="$REPO_MODULES_DIR/.modulerc"


    # Path to the bin directory where all the containerised environment binaries are stored
    export ENV_BIN_DIR="$ENV_VERSION_DIR/bin"

    # Set launcher script name
    export LAUNCHER_SCRIPT_NAME=launcher.sh
    # Path to the launcher script
    export LAUNCHER_SCRIPT_PATH="$ENV_BIN_DIR/$LAUNCHER_SCRIPT_NAME"
    # Path to the defaults launcher script within the repository
    export REPO_LAUNCHER_SCRIPT_PATH="$SCRIPTS_DIR/$LAUNCHER_SCRIPT_NAME"

    # Path to the defaults built container image in the repository.
    # This image is automatically built by the build_container_image.yml workflow
    export REPO_CONTAINER_IMAGE_PATH="$DEFAULTS_DIR/container/base_image.sif"
    # Path to the container image to be used at runtime
    export RUNTIME_CONTAINER_IMAGE_PATH="$ENV_VERSION_DIR/$(basename "$REPO_CONTAINER_IMAGE_PATH")"

    # Name of the created squashfs file
    export SQSH_FILENAME=overlay.sqsh
    # Full path to the created squashfs file in the temporary directory
    export TEMP_SQSH_FILE_PATH="$TEMP_WORKING_DIR/$SQSH_FILENAME"
    # Full path to the squashfs file
    export SQSH_FILE_PATH="$ENV_VERSION_DIR/$SQSH_FILENAME"


    # Name of the environment lock file
    env_lock_filename=env_spec_lock.yml
    # Full path to the environment lock file
    export ENV_LOCK_FILE_PATH="$ENV_VERSION_DIR/$env_lock_filename"
    # Environment specification file
    if [[ "$DEPLOYMENT_STAGE" == PRODUCTION ]]; then
        # If the deployment is for PRODUCTION, use the specification lock file produced in the STAGING deployment
        if [[ "$ENV_TYPE" == STABLE ]]; then
            # For a STABLE env, take the ENV_LOCK_FILE_PATH and replace the initial BASE_DIR with the STABLE_STAGING_BASE_DIR
            env_spec_path=$STABLE_STAGING_BASE_DIR/${ENV_LOCK_FILE_PATH#$BASE_DIR/}
        else
            # For a DEVELOPMENT env, take the ENV_LOCK_FILE_PATH and replace the initial BASE_DIR with the DEVELOPMENT_STAGING_BASE_DIR
            env_spec_path=$DEVELOPMENT_STAGING_BASE_DIR/${ENV_LOCK_FILE_PATH#$BASE_DIR/}
        fi
        if [ ! -f "$env_spec_path" ]; then
            echo "Error! Staging environment lock file '$env_spec_path' not found!" >&2
            exit 1
        fi
    else
        # If the deployment is for STAGING, use the specification from the repository
        if [[ "$ENV_TYPE" == STABLE ]]; then
            # 'environment.yml' for STABLE environments
            env_spec_path="$env_folder/environment.yml"
        else
            #' environment_dev.yml' for DEVELOPMENT environments
            env_spec_path="$env_folder/environment_dev.yml"
        fi
        if [ ! -f "$env_spec_path" ]; then
            echo "Error! Environment file '${env_spec_path#$REPO_PATH/}' not found in the repository!" >&2
            exit 1
        fi
    fi
    export ENV_FILE="$env_spec_path"

    # Maximum number of DEVELOPMENT environment versions to keep in PRODUCTION simultaneously.
    # If a new deployment causes the total to exceed this limit, the oldest version is deleted.
    export MAX_DEV_ENV_VERSIONS=3

    ### Micromamba initialisation
    # MAMBA_INSTALLATION_DIR is the directory where the micromamba executable used to manage environments is 
    # installed if no custom MAMBA_EXE is used.
    export mamba_installation_dir="${MAMBA_INSTALLATION_DIR:-"$containerised_envs_root_dir/micromamba_installation"}"
    # MAMBA_EXE is the env variable that gets actually used to manage environment. If MAMBA_EXE is not defined or not found, 
    # mamba_default_exe gets used instead. If mamba_default_exe cannot be found, micromamba gets initialised by installing the latest
    # version of micromamba to the the mamba_default_exe path.
    mamba_default_exe="$mamba_installation_dir/bin/micromamba"
    export MAMBA_EXE="${MAMBA_EXE:-$mamba_default_exe}"
    export mamba_download_url='https://micro.mamba.pm/api/micromamba/linux-64/latest'
    # If the micromamba executable is not found or not executable, the latest version is installed
    if [ ! -x "$MAMBA_EXE" ]; then
        if [ ! -f "$MAMBA_EXE" ]; then # Micromamba exe not found
            echo "Micromamba executable '$MAMBA_EXE' not found."
        else # Micromamba exe not executable
            echo "Micromamba executable '$MAMBA_EXE' is not executable."
        fi

        if [ ! -x "$mamba_default_exe" ]; then # Default micromamba exe not executable 
            if [ ! -f "$mamba_default_exe" ]; then # Default micromamba exe not found
                mkdir -p $(dirname "$mamba_default_exe")
                # Get micromamba latest version
                echo "Installing micromamba's latest version:"
                curl -L "$mamba_download_url" | tar -xvjO bin/micromamba > "$mamba_default_exe"
            fi
            # Set executable permissions
            chmod u+x "$mamba_default_exe"
            set_perms "$mamba_default_exe"
        fi
        MAMBA_EXE="$mamba_default_exe"
        echo "Using micromamba executable: $MAMBA_EXE"
    fi
    # Set ENV_PROMPT_MODIFIER
    export ENV_PROMPT_MODIFIER="${ENV_PROMPT_MODIFIER:-"($MODULE_NAME-$MODULE_VERSION) "}"

    ### jq initialisation
    # If the jq executable is not found or not executable, the latest version is installed
    if [ ! -x "$JQ_EXE" ]; then
        if [ -z "$JQ_EXE" ]; then
            echo "jq executable not provided."
        elif [ ! -f "$JQ_EXE" ]; then
            echo "jq executable '$JQ_EXE' not found."
        else
            echo "jq executable '$JQ_EXE' is not executable."
        fi
        # Create a temporary directory for the jq installation and clean it up on exit
        jq_dir=$(mktemp -d)
        trap_append "rm -vrf $jq_dir" EXIT
        JQ_EXE="$jq_dir/jq"
        jq_download_url='https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64'
        echo "Installing jq's latest version:"
        curl -L "$jq_download_url" --output "$JQ_EXE"
        # Set executable permissions
        chmod u+x "$JQ_EXE"
        set_perms "$JQ_EXE"
    fi

    ### Other settings
    # Don't include user local Python packages in the Python environment
    export PYTHONNOUSERSITE=${PYTHONNOUSERSITE:-true}
    # Disable Python's bytecode cache (.pyc files)
    export PYTHONDONTWRITEBYTECODE=${PYTHONDONTWRITEBYTECODE:-1}

    # Set directories to bind to the singularity container using --bind
    bind_dirs=(
        /etc
        /half-root
        /local
        /ram
        /run
        /system
        /usr
        /var/lib/sss
        /var/lib/rpm
        /var/run/munge
        /sys/fs/cgroup
        /iointensive
        /home
    )
    valid_bind_dirs=()
    for bind_dir in "${bind_dirs[@]}"; do
    [ -d "$bind_dir" ] && valid_bind_dirs+=("$bind_dir")
    done
    # Join bind_dirs together with a comma. 
    export BIND_STR=$(IFS=,; printf '%s\n' "${valid_bind_dirs[*]}")

    # Additional paths to squashfs environments to overlay to the container at runtime using --overlay
    # Different paths should be separated by a comma
    # (e.g., `/path/to/firs/env.sqsh,/path/to/another/environment.sqsh`)
    # These should be defined in the specific environment's config.sh file if needed.
    export ADDITIONAL_CONTAINER_OVERLAYS="${ADDITIONAL_CONTAINER_OVERLAYS:-""}"


    # Executables in the environment never symlinked to the launcher script.
    # These executables will always run on the host using its PATH, and not inside the 
    # Singularity container, even if they are present in the environment's bin directory.
    # Therefore, their executed version may differ from the environment's installed version.
    # Different executables should be separated by a comma
    # (e.g., `ssh,clear`)
    # These should be defined in the specific environment's config.sh file if needed.
    default_host_executables="ssh,clear,display"
    export HOST_EXECUTABLES="${HOST_EXECUTABLES:-$default_host_executables}"

    # ### Define any undefined arrays - TODO: modify this logic?
    # _ARRAYS=(
    #     rpms_to_remove
    #     replace_from_apps
    #     outside_commands_to_include
    #     outside_files_to_copy
    #     replace_with_external
    # )
    # for var in "${_ARRAYS[@]}"; do
    #   [[ -z ${!var+x} ]] && declare -a "$var=()"
    # done
fi