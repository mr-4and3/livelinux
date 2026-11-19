#!/bin/bash
# This script manages the version number of the project. It allows you to initialize the version number, increment the patch, minor, or major version, and updates the version_num.sh file accordingly.

main() {
    local DefaultMajor=0
    local DefaultMinor=1
    local DefaultPatch=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                echo "Usage: $0 [--init-version] [--patch] [--minor] [--major]"
                echo "Options:"
                echo "  --init-version    Initialize version number"
                echo "  --patch           Increment patch version"
                echo "  --minor           Increment minor version"
                echo "  --major           Increment major version"
                exit 0
                ;;                
            init|patch|minor|major)
                POSITIONAL+=("$1")
                shift
                break
                ;;
            *)
                error "Unknown parameter: $1"
                echo "Usage: $0 [--init-version] [--patch] [--minor] [--major]"
                exit 1
                ;;
        esac
    done

    # Check if version_num.sh exists and source it, otherwise initialize version number
    if [ "${POSITIONAL[0]}" == "init" ]; then
        write_version_num ${DefaultMajor} ${DefaultMinor} ${DefaultPatch}
    fi

    # load version_num.sh if it exists, otherwise initialize version number
    if [ -f "version_num.sh" ]; then
        source version_num.sh
        if [ -z "$VERSION" ] || [ -z "$MAJOR" ] || [ -z "$MINOR" ] || [ -z "$PATCH" ]; then
            write_version_num ${DefaultMajor} ${DefaultMinor} ${DefaultPatch}
        
        fi
    else
        write_version_num ${DefaultMajor} ${DefaultMinor} ${DefaultPatch}
    fi

    if [ "${POSITIONAL[0]}" == "patch" ]; then
        PATCH=$((PATCH + 1))
    elif [ "${POSITIONAL[0]}" == "minor" ]; then
        MINOR=$((MINOR + 1))
        PATCH=0
    elif [ "${POSITIONAL[0]}" == "major" ]; then
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
    fi

    VERSION="${MAJOR}.${MINOR}.${PATCH}"
    write_version_num ${MAJOR} ${MINOR} ${PATCH}
}

write_version_num() {
    local MAJOR=${1:-0}
    local MINOR=${2:-1}
    local PATCH=${3:-0}
    echo "Set version to ${MAJOR}.${MINOR}.${PATCH}"
    cat <<EOL > version_num.sh
#!/bin/bash

MAJOR=$MAJOR
MINOR=$MINOR
PATCH=$PATCH
# shellcheck disable=SC2034
VERSION=\${MAJOR}.\${MINOR}.\${PATCH}
EOL
    sed -i "0,/^version = /s/^version = .*/version = \"$VERSION\"/" safe-stick/Cargo.toml
    echo "Version number initialized."
    exit 0
}

main "$@"