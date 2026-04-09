# The double underscore variables within this file are replaced by the 'replace_dunder_variables'
# function within the build.sh or deploy.sh scripts

env_path='__INTERNAL_ENV_DIR__'
env_bin_path='__INTERNAL_ENV_BIN_DIR__'

# Prepend path with continerised environment bin directory
export PATH="$env_bin_path:$PATH"
# Set CONDA_DEFAULT_ENV
export CONDA_DEFAULT_ENV="$env_path"
# Set CONDA_PREFIX
export CONDA_PREFIX="$env_path"
# Set CONDA_PROMPT_MODIFIER
export CONDA_PROMPT_MODIFIER="__ENV_PROMPT_MODIFIER__"

# Payu specific environment variables
export ENV_LAUNCHER_SCRIPT_PATH="__LAUNCHER_SCRIPT_PATH__"

for file in "$env_path"/conda/activate.d/*.sh; do
    if [ -r "$file" ]; then
        . "$file"
    fi
done
