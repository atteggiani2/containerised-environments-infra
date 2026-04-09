### Useful functions
function trap_append() {
    # To run similarly to the `trap` command (e.g., trap CMD SIG), but instead of replacing the
    # existing trap command for the signal, it appends the command to the existing ones.
    # To refer to the exit status of the whole script within the trap_append commands, use the variable
    # `_exit_status` (e.g., `if [ $_exit_status -ne 0 ]; then ...`) which is automatically
    # initialised to capture the exit status of the script when the signal is triggered.
    local cmd sig existing_cmds
    
    cmd="$1"
    sig="$2"
    existing_cmds=$(trap -p "$sig")
    # Remove `trap -- '` from the existing_cmds output
    existing_cmds=${existing_cmds#"trap -- '"}
    # Remove `' <SIG>` from the existing_cmds output
    existing_cmds=${existing_cmds%"' $sig"}
    # If there are no existing commands, we initialise the existing_cmds to capture the exit
    # status in the `_exit_status` variable.
    # This because we cannot use `$?` directly within the trap_append commands, because it would capture
    # the exit status of the previous command executed within the trap_append commands, which might not
    # be the original exit status of the script.
    if [[ -z "$existing_cmds" ]]; then
        existing_cmds='_exit_status=$? ; '
    fi
    # Run trap by appending the current command to the existing ones
    trap "${existing_cmds}${cmd} ; " "$sig"
}

function delete_version() {
    # Delete all files and folders associated with a version, which are listed in the manifest $1.
    # If $1 is not provided, it defaults to the MANIFEST_FILE_PATH for the current environment version.
    local manifest_file="${1:-$MANIFEST_FILE_PATH}"
    if [[ ! -f "$manifest_file" ]]; then
        echo "Error: manifest file '$manifest_file' not found." >&2
        return 1
    fi
    # Make sure to split the manifest by newlines and not by spaces (-d '\n')
    # Do not run if the manifest is empty (--no-run-if-empty)
    xargs --no-run-if-empty -d '\n' rm -vrf < "$manifest_file"
}

function in_array() {
    # Assumes first arg is the string to search for and the others are an array
    local string item
    string="$1"
    shift
    for item in "$@"; do
        [[ "$item" == "$string" ]] && return 0
    done
    return 1
}

function set_perms() {
    # Set the permissions for each of the provided arguments
    local arg
    for arg in "$@"; do
        if [[ -L "${arg}" ]]; then # Links
            # Change group ownership for the link (not the file it points to)
            chgrp -h "${GROUP_OWNER}" "${arg}"
        elif [[ -d "${arg}" ]]; then # Directories
            # Change group ownership recursively
            chgrp -R "${GROUP_OWNER}" "${arg}"
            # Set group permissions recursively to match user permissions without "write"
            # and remove all permissions for others
            chmod -R g=u-w,o= "${arg}"
            # Set group ID bit, to have all children files and directories inherit the directory's group
            chmod g+s "${arg}"
            # Set specific permissions to OWNER recursively to read, write and execute 
            # (only if someone else already has execute) permissions, also for new files and directories
            setfacl -R -m u:"${OWNER}":rwX,d:u:"${OWNER}":rwX "${arg}"
        elif [[ -f "${arg}" ]]; then # Files
            # reset any existing acls
            setfacl -b "${arg}"
            # Change group ownership
            chgrp "${GROUP_OWNER}" "${arg}"
            # Set group permissions to match user permissions without "write"
            # and remove all permissions for others
            chmod g=u-w,o= "${arg}"
            # Set specific permissions to OWNER to read, write and execute 
            # (only if someone else already has execute) permissions
            setfacl -m u:"${OWNER}":rwX "${arg}"
        fi
    done
}

function copy_if_changed() {
    # Copy the file at $1 to $2 only if the destination doesn't exist or differs.
    # Behavior:
    # 1. If $2 is a directory: copy $1 into $2 using $1's basename if missing or different.
    # 2. If $2 is a file: copy $1 over it if contents differ.
    # 3. If $2 doesn't exist but its parent directory exists: copy $1 to $2's location.
    # Also set the correct permissions for the copied file using `set_perms` function.

    local src dest target parent_dir 
    src="$1"
    dest="$2"

    if [ -d "$dest" ]; then
        # Destination is a directory: copy into it using $1's basename
        target="$dest/$(basename "$src")"
    else
        # Destination is a file or doesn't exist: copy to that path
        target="$dest"
    fi
    # Ensure the parent directory exists before copying
    parent_dir=$(dirname "$target")
    if [ ! -d "$parent_dir" ]; then
        echo "Error: trying to copy to '$target' but parent directory '$parent_dir' does not exist" >&2
        return 1
    fi

    # Copy only if missing or contents differ
    if [ ! -e "$target" ]; then
        cp "$src" "$target"
        echo "Created '$target'"
    elif ! cmp -s "$src" "$target"; then
        cp "$src" "$target"
        echo "Updated '$target'"
    fi
}

function _replace_dunder_variables() {
    # Replace the double underscore (dunder) variables in $1 with values from the environment,
    # and outputs the replaced content.
    # E.g. "__MY_VAR__" is replaced with the value of MY_VAR. 
    # If a variable that should have been replaced is not found, an error is thrown.
    # !!IMPORTANT!! dunder variables within commented lines are replaced too!
    local file content vars var name value
    file="$1"
    # Read the file content into a variable to be modified without modifying the file
    content=$(<"$file")
    # Catch all unique variables to replace
    vars=$(grep -oE '__[A-Z0-9_]+__' "$file" | sort -u)
    for var in $vars; do
        # Remove double undescores
        name="${var#__}"
        name="${name%__}"
        if [[ -z "${!name+x}" ]]; then
            # If the variable is not defined in the environment raise an error
            echo "Error: environment variable '$name' to replace within '$file' is not defined" >&2
            return 1
        fi
        value="${!name}"
        # Escape characters in 'value' that are special sed replacements characters to avoid problems
        # in the replacements.
        # Sed special characters are `&`, `\` and the character we choose as sed command delimiter (`|`)
        # Also, within this value replacement command, we use `/` as a sed delimiter so the command is
        # clearer as we don't have to escape the `|` character. We also have to escape the backslash (`\\`)
        value=$(printf '%s' "$value" | sed 's/[&|\\]/\\&/g')
        # Replace characters (using `|` as a sed delimiter as mentioned above)
        content=$(printf '%s' "$content" | sed "s|$var|$value|g")
    done
    # Output the final modified content
    printf '%s' "$content"
}

function copy_if_changed_with_replace() {
    # Replace the double underscore (dunder) variables in $1 with values from the environment
    # E.g. "__MY_VAR__" is replaced with the value of MY_VAR. 
    # If a variable that should have been replaced is not found, an error is thrown.
    # Then, copy the replaced version of $1 to $2, but only if $2 doesn't exist 
    # or content of the replaced $1 is different from $2

    local tmpdir tmpfile
    # Create a temporary file to store the replaced $1
    # We create a temporary directory and then we set the filename within
    # because we need the filename to be exactly the same as $1.
    tmpdir=$(mktemp -d)
    # Clean up temporary directory on exit
    trap_append "rm -rf $tmpdir" EXIT
    # Set the temporary file path within the temporary directory with the same basename as $1
    tmpfile="$tmpdir/$(basename "$1")"
    # Store the replaced version of $1 in a the file
    _replace_dunder_variables "$1" > "$tmpfile"
    # Copy the replaced version of $1 to $2
    copy_if_changed "$tmpfile" "$2"
}

function get_overrides_or_defaults() {
    # This function checks for the existence of a correspondent override file for the default $1. 
    # If an override file exists, it returns its path. Otherwise, it returns $1.
    # If $1 is not found in either default or override locations, an error is raised.
    # $2 is used to provide an error message.

    local file overrides_file
    
    file="$1"

    # Get override file path by replacing the $DEFAULTS_DIR part of the default file path with $ENV_OVERRIDES_DIR
    overrides_file="${file/#$DEFAULTS_DIR/$ENV_OVERRIDES_DIR}"

    # If the overrides file exists, we use it, otherwise we use the default file. 
    # If neither of them exists, we raise an error.
    if [[ -f "$overrides_file" ]]; then
        file="$overrides_file"
    elif [[ ! -f "$file" ]]; then
        echo "$2" >&2
        exit 1
    fi
    printf '%s' "$file"
}