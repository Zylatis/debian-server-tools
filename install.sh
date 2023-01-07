#!/bin/bash
#
# Install a tool from debian-server-tools.
#
# VERSION       :0.5.0
# DATE          :2018-07-26
# AUTHOR        :Viktor Szépe <viktor@szepe.net>
# LICENSE       :The MIT License (MIT)
# URL           :https://github.com/szepeviktor/debian-server-tools
# BASH-VERSION  :4.2+

Die()
{
    local -i RET="$1"

    shift
    echo -e "$*" 1>&2
    exit "$RET"
}

#####################################################
# Parses out a meta value from a script
# Arguments:
#   FILE
#   META
#####################################################
Get_meta()
{
    # Defaults to self
    local FILE="${1:-$0}"
    # Defaults to "VERSION"
    local META="${2:-VERSION}"
    local VALUE

    VALUE="$(head -n 30 "$FILE" | grep -m 1 "^# ${META}\\s*:" | cut -d ":" -f 2-)"

    if [ -z "$VALUE" ]; then
        VALUE="(unknown)"
    fi
    echo "$VALUE"
}

#####################################################
# Parses out all meta values from a script
# Arguments:
#   FILE
#   META
#####################################################
Get_meta_all()
{
    # Defaults to self
    local FILE="${1:-$0}"
    # Defaults to "VERSION"
    local META="${2:-VERSION}"
    local VALUE

    VALUE="$(head -n 30 "$FILE" | grep "^# ${META}\\s*:" | cut -d ":" -f 2-)"

    if [ -z "$VALUE" ]; then
        VALUE="(unknown)"
    fi
    echo "$VALUE"
}

#####################################################
# Copies files in place, sets permissions and owner
# Arguments:
#   FILE
#####################################################
Do_install()
{
    local FILE="$1"
    local OWNER
    local PERMS
    local SYMLINK
    local SCRIPT
    local PKG

    if [ ! -f "$FILE" ]; then
        Die 1 "File does not exist (${FILE})"
    fi

    SCRIPT="$(Get_meta "$FILE" LOCATION)"
    if [ -z "$SCRIPT" ] || [ "$SCRIPT" == "(unknown)" ]; then
        Die 2 "Invalid location (${SCRIPT})"
    fi
    OWNER="$(Get_meta "$FILE" OWNER)"
    if [ -z "$OWNER" ] || [ "$OWNER" == "(unknown)" ]; then
        OWNER="root:staff"
    fi
    PERMS="$(Get_meta "$FILE" PERMISSION)"
    if [ -z "$PERMS" ] || [ "$PERMS" == "(unknown)" ]; then
        PERMS="0755"
    fi

    # Check for existence
    if [ -f "$SCRIPT" ]; then
        if diff -q "$FILE" "$SCRIPT" &> /dev/null; then
            echo "Already up-to-date ${SCRIPT}"
            return
        fi

        echo "Updating ${SCRIPT}"
    else
        echo "Installing ${FILE} to ${SCRIPT}"
    fi

    # Install
    install -v -D --no-target-directory --preserve-timestamps \
        --owner="${OWNER%:*}" --group="${OWNER#*:}" --mode "$PERMS" \
        "$FILE" "$SCRIPT" \
        || Die 11 "Installation failure (${FILE})"

    # Create symlink
    head -n 30 "$FILE" | grep '^# SYMLINK\s*:' | cut -d ":" -f 2- \
        | while read -r SYMLINK; do
            echo -n "Symlinking "
            ln -s -v -f "$SCRIPT" "$SYMLINK" || Die 12 "Symbolic link creation failure (${SYMLINK})"
        done

    # Cron jobs
    if head -n 30 "$FILE" | grep -q -i '^# CRON'; then
        "$(dirname "$0")/install-cron.sh" "$FILE" || Die 13 "Cron installation failure (${FILE})"
    fi

    # Display dependencies
    Get_meta_all "$FILE" DEPENDS
    # Check APT dependencies
    Get_meta_all "$FILE" DEPENDS | sed -n -e 's/^apt-get install \(.\+\)$/\1 /p' \
        | while read -r -d " " PKG; do
            if [ "$(dpkg-query --showformat="\${Status}" --show "$PKG" 2> /dev/null)" != "install ok installed" ]; then
                echo "MISSING DEPENDENCY: apt-get install ${PKG}" 1>&2
            fi
        done
    # Check PyPA dependencies
    Get_meta_all "$FILE" DEPENDS | sed -n -e 's/^pip install \(.\+\)$/\1 /p' \
        | while read -r -d " " PKG; do
            if ! pip show "$PKG" | grep -q -x 'Version: \S\+'; then
                echo "MISSING DEPENDENCY: pip install ${PKG}" 1>&2
            fi
        done
    Get_meta_all "$FILE" DEPENDS | sed -n -e 's/^pip3 install \(.\+\)$/\1 /p' \
        | while read -r -d " " PKG; do
            if ! pip3 show "$PKG" | grep -q -x 'Version: \S\+'; then
                echo "MISSING DEPENDENCY: pip3 install ${PKG}" 1>&2
            fi
        done
    # Check file dependencies
    Get_meta_all "$FILE" DEPENDS | sed -n -e 's|^\(/.\+\)$|\1|p' \
        | while read -r PKG; do
            test -x "$PKG" || echo "MISSING DEPENDENCY: Install '${PKG}'" 1>&2
        done
}

#####################################################
# Process all files in a directory NOT recursively
# Arguments:
#   DIR
#####################################################
Do_dir()
{
    local DIR="$1"
    local FILE

    find "$DIR" -maxdepth 1 -type f \
        | while read -r FILE; do
            Do_install "$FILE"
        done
}


#########################################################

INSTALL_PATH="$1"

# Check user
if [[ $EUID -ne 0 ]]; then
    Die 1 "Only root is allowed to install"
fi

# Display version
if [ "$INSTALL_PATH" == "--version" ]; then
    Get_meta
    exit 0
fi

if [ -d "$INSTALL_PATH" ]; then
    Do_dir "$INSTALL_PATH"
elif [ -f "$INSTALL_PATH" ]; then
    Do_install "$INSTALL_PATH"
else
    Die 2 "Specified path does not exist (${INSTALL_PATH})"
fi
