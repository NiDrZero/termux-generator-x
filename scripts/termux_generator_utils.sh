# Funktion, um flüchtige Netzwerkfehler beim Klonen abzufangen (z.B. HTTP/2
# stream resets, connection resets) durch mehrere Versuche mit Backoff.
# Usage: git_clone_retry <git clone args...>
# NOTE: assumes the destination directory is always the last argument,
# which holds for every call site in this repo.
git_clone_retry() {
    local max_attempts=3
    local delay=5
    local attempt=1
    local dest="${*: -1}"

    while (( attempt <= max_attempts )); do
        # A previous attempt that died mid-transfer (killed process, dropped
        # connection) can leave a non-empty partial checkout behind, which
        # makes git refuse to retry with "destination path already exists
        # and is not an empty directory". Clear it before every attempt.
        rm -rf -- "$dest"

        if git clone "$@"; then
            return 0
        fi

        local status=$?
        echo "[!] git clone failed (exit ${status}, attempt ${attempt}/${max_attempts}): git clone $*" >&2

        if (( attempt < max_attempts )); then
            echo "[*] Retrying in ${delay}s..." >&2
            sleep "$delay"
            delay=$(( delay * 2 ))
        fi
        (( attempt++ ))
    done

    rm -rf -- "$dest"
    echo "[!] git clone permanently failed after ${max_attempts} attempts: git clone $*" >&2
    return 1
}

portable_sed_i() {
    if sed v </dev/null 2> /dev/null; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

apply_patches() {
    local srcdir=$(realpath "$1")
    local targetdir=$(realpath "$2")

    if [ ! -d "$srcdir" ]; then
        echo "[*] No patches directory found at $srcdir. Skipping."
        return
    fi

    pushd "$targetdir" > /dev/null

    # Find and sort patch files
    local patches=$(find "$srcdir" -maxdepth 1 -name "*.patch" | sort)

    if [ -z "$patches" ]; then
        echo "[*] No .patch files found in $srcdir. Skipping."
    else
        for patch in $patches; do
            echo "[*] Applying patch: $(basename "$patch")"
            if ! patch -p1 < "$patch"; then
                echo "[!] Failed to apply patch: $(basename "$patch")"
                exit 1
            fi
        done
    fi

    popd > /dev/null
}

replace_termux_name() {
    if [[ "$TERMUX_APP__PACKAGE_NAME" == "com.termux" ]]; then
        return
    fi
    local targetdir="$1"
    local replacement_name="$2"
    local replacement_name_underscore="$(echo "$replacement_name" | tr . _)"
    local replacement_name_slash="$(echo "$replacement_name" | tr . /)"

    if [ ! -d "$targetdir" ]; then
        echo "[*] Target directory $targetdir not found. Skipping name replacement."
        return
    fi

    pushd "$targetdir" > /dev/null
    
    echo "[*] Replacing 'com.termux' with '$replacement_name' in $targetdir..."
    
    # Process only text files to avoid errors with binaries
    # Using a more robust way to find text files and avoiding permission denied errors
    find . -type f -not -path '*/.*' 2>/dev/null | while read -r file; do
        if file "$file" 2>/dev/null | grep -q "text"; then
            portable_sed_i -e "s|>Termux<|>$replacement_name<|g" \
                           -e "s|\"Termux\"|\"$replacement_name\"|g" \
                           -e "s|Termux:|$replacement_name:|g" \
                           -e "s|com\.termux|$replacement_name|g" \
                           -e "s|com_termux|$replacement_name_underscore|g" \
                           -e '/https\?:\/\//!s|com/termux|'$replacement_name_slash'|g' "$file"
        fi
    done

    popd > /dev/null
}

# Funktion, um Ordner zu migrieren
migrate_termux_folder() {
    if [[ "$TERMUX_APP__PACKAGE_NAME" == "com.termux" ]]; then
        return
    fi
    local parentdir="$(dirname "$(dirname "$1")")"
    local replacement_name="$2"
    local destination="${parentdir}/$(echo "$replacement_name" | tr . /)/"

    echo "Migrating folder:"
    echo "- ${parentdir}/com/termux/"
    echo "to"
    echo "+ ${destination}"
    mkdir -p "${destination}"
    mv "${parentdir}/com/termux/"* "${destination}"
    rm -r "${parentdir}/com/termux/"
}

migrate_termux_folder_tree() {
    if [[ "$TERMUX_APP__PACKAGE_NAME" == "com.termux" ]]; then
        return
    fi
    local targetdir="$1"
    local replacement_name="$2"

    pushd "$targetdir"

    # Vollständig macOS-kompatible Variante für Verzeichnismigration
    local dir
    find "$(pwd)" -type d -name termux | grep -v -e 'shared/termux' -e 'settings/termux' | while read -r dir; do
        migrate_termux_folder "$dir" "$replacement_name"
    done

    popd
}
