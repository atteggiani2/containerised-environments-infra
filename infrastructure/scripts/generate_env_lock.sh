# This file is sourced in the build_and_deploy_env.sh script to generate a lock file 
# for the containerised environment.
# It generate an environment lock file using `micromamba env export`, then removes the
# 'prefix:' line and sets the environment name to $MODULE_NAME-$MODULE_VERSION.
# It also changes pip-installed packages specification to be taken from the `pip freeze` command,
# to ensure the exact versions (commit hashes) of pip-installed packages are captured.

# Generate a temporary file for the lock file, and ensure it is removed on exit
temp_env_lock_file=$(mktemp)
trap_append "rm -f $temp_env_lock_file" EXIT

# Generate the environment lock file, remove the 'prefix: ...' line 
# and set the environment name to $MODULE_NAME-$MODULE_VERSION
"$MAMBA_EXE" env export --prefix "$TEMP_ENV_DIR" --no-rc --no-env \
    | sed -e '/^prefix:/d' \
          -e "s|^name:.*|name: $MODULE_NAME-$MODULE_VERSION|" \
    > "$temp_env_lock_file"

# Use awk to get pip-installed git packages from pip freeze output,
# and then replace those in the env lock file
awk '
# Execute the first set of commands only for the first file (pip freeze output).
# NR --> Total number of records processed (i.e. lines)
# FNR --> Number of records processed (i.e. lines) in the current file
# NR==FNR is true only while reading the first file
NR==FNR {
    if ($0 ~ /^[^ @]+ @ git\+/) { # Line matches the pattern for git-installed packages
        # Get package name and git specification
        idx = index($0, " @ ") # Split on " @ " to separate package name and git spec
        pkg = tolower(substr($0, 1, idx-1)) # Get package name (lowercase)
        gitspec = substr($0, idx+3)  # Get git specification
        specs[pkg] = gitspec # Store in specs array to use in the next set of commands
    }
    next  # Go to next line. Do not process lines that are not match git-installed packages
}

# Detect the start of the pip section in the lock file
/^  - pip:/ { # pip freeze output would never match this
    in_pip = 1 # set a variable to indicate we are in the pip section
    print # print the start of pip section
    next # Go to next line
}

# Process pip package lines
in_pip && /^    - / {
    line = $0
    sub(/^    - /, "", line)   # strip the leading "    - " to get "pkg==version"
    sub(/==.*/, "", line)      # strip "==version" to get just the package name
    pkg = tolower(line)
    if (pkg in specs) { # If the package was installed from git
        # Replace with the git spec from pip freeze
        print "    - " specs[pkg]
    } else { # Otherwise, keep the original line
        print $0
    }
    next # Go to next line
}

# Detect the end of the pip section
in_pip && !/^    - / {
    in_pip = 0
}

# Print all other lines unchanged
{ print }
' <("$TEMP_ENV_DIR/bin/python3" -m pip freeze) "$temp_env_lock_file"