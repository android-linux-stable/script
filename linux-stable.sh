#!/usr/bin/env bash
#
# Pull in linux-stable updates to a kernel tree
#
# Copyright (C) 2017-2018 Nathan Chancellor
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>


# Colors for script
BOLD="\033[1m"
GRN="\033[01;32m"
RED="\033[01;31m"
RST="\033[0m"
YLW="\033[01;33m"


# Alias for echo to handle escape codes like colors
function echo() {
    command echo -e "$@"
}


# Prints a formatted header to point out what is being done to the user
function header() {
    if [[ -n ${2} ]]; then
        COLOR=${2}
    else
        COLOR=${RED}
    fi
    echo "${COLOR}"
    # shellcheck disable=SC2034
    echo "====$(for i in $(seq ${#1}); do echo "=\c"; done)===="
    echo "==  ${1}  =="
    # shellcheck disable=SC2034
    echo "====$(for i in $(seq ${#1}); do echo "=\c"; done)===="
    echo "${RST}"
}


# Prints an error in bold red
function report_error() {
    echo
    echo "${RED}${1}${RST}"
    if [[ ${2} = "-h" ]]; then
        ${0} -h
    fi
    exit 1
}


# Prints a warning in bold yellow
function report_warning() {
    echo
    echo "${YLW}${1}${RST}"
    if [[ -z ${2} ]]; then
        echo
    fi
}

# Parse the provided parameters
function parse_parameters() {
    while [[ $# -ge 1 ]]; do
        case ${1} in
            # Use git cherry-pick
            "-c"|"--cherry-pick")
                UPDATE_METHOD=cherry-pick ;;

            # Only update the linux-stable remote
            "-f"|"--fetch-only")
                FETCH_REMOTE_ONLY=true ;;

            # Help menu
            "-h"|"--help")
                echo
                echo "${BOLD}Command:${RST} ./$(basename "${0}") <options>"
                echo
                echo "${BOLD}Script description:${RST} Merges/cherry-picks Linux upstream into a kernel tree"
                echo
                echo "${BOLD}Required parameters:${RST}"
                echo "    -c | --cherry-pick"
                echo "    -m | --merge"
                echo "        Call either git cherry-pick or git merge when updating from upstream"
                echo
                echo "${BOLD}Optional parameters:${RST}"
                echo "    -f | --fetch-only"
                echo "        Simply fetches the tags from linux-stable then exits"
                echo
                echo "    -k | --kernel-folder"
                echo "        The device's kernel source's location; this can either be a full path or relative to where the script is being executed."
                echo
                echo "    -l | --latest"
                echo "        Updates to the latest version available for the current kernel tree"
                echo
                echo "    -p | --print-latest"
                echo "        Prints the latest version available for the current kernel tree then exits"
                echo
                echo "    -v | --version"
                echo "        Updates to the specified version (e.g. -v 3.18.78)"
                echo
                echo "${BOLD}Defaults:${RST}"
                echo "    If -l or -v are not specified, ONE version is picked at a time (e.g. 3.18.31 to 3.18.32)"
                echo
                echo "    If -k is not specified, the script assumes it is in the kernel source folder already"
                echo
                exit 1 ;;

            # Kernel source location
            "-k"|"--kernel-folder")
                shift
                if [[ $# -lt 1 ]]; then
                    report_error "Please specify a kernel source location!!"
                fi

                KERNEL_FOLDER=${1} ;;

            # Update to the latest version upstream unconditionally
            "-l"|"--latest")
                UPDATE_MODE=1 ;;

            # Use git merge
            "-m"|"--merge")
                UPDATE_METHOD=merge ;;

            # Print the latest version from kernel.org
            "-p"|"--print-latest")
                PRINT_LATEST=true ;;

            # Update to the specified version
            "-v"|"--version")
                shift
                if [[ $# -lt 1 ]]; then
                    report_error "Please specify a version to update!"
                fi

                TARGET_VERSION=${1} ;;

            *)
                report_error "Invalid parameter!" ;;
        esac

        shift
    done

    # If kernel source isn't specified, assume we're there
    if [[ -z ${KERNEL_FOLDER} ]]; then
        KERNEL_FOLDER=$(pwd)
    fi

    # Sanity checks
    if [[ ! ${UPDATE_METHOD} ]]; then
        report_error "Neither cherry-pick nor merge were specified, please supply one!" -h
    elif [[ ! -d ${KERNEL_FOLDER} ]]; then
        report_error "Invalid kernel source location, folder does not exist!" -h
    elif [[ ! -f ${KERNEL_FOLDER}/Makefile ]]; then
        report_error "Invalid kernel source location, no Makefile present!" -h
    fi

    # Default update mode is one version at a time
    if [[ -z ${UPDATE_MODE} ]]; then
        UPDATE_MODE=0
    fi
}


# Update the linux-stable remote (and add it if it doesn't exist)
function update_remote() {
    header "Updating linux-stable"

    # Add remote if it isn't already present
    cd "${KERNEL_FOLDER}" || report_error "Could not change into ${KERNEL_FOLDER}!"

    if ! git fetch --tags https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git/; then
        report_error "linux-stable update failed!"
    else
        echo "linux-stable updated successfully!"
    fi

    if [[ ${FETCH_REMOTE_ONLY} ]]; then
        echo
        exit 0
    fi
}


# Generate versions
function generate_versions() {
    header "Calculating versions"

    # Full kernel version
    CURRENT_VERSION=$(make kernelversion)
    # First two numbers (3.4 | 3.10 | 3.18 | 4.4)
    CURRENT_MAJOR_VERSION=$(echo "${CURRENT_VERSION}" | cut -f 1,2 -d .)
    # Last number
    CURRENT_SUBLEVEL=$(echo "${CURRENT_VERSION}" | cut -d . -f 3)

    # Get latest update from upstream
    LATEST_VERSION=$(git tag --sort=-taggerdate -l v"${CURRENT_MAJOR_VERSION}"* | head -n 1 | sed s/v//)
    LATEST_SUBLEVEL=$(echo "${LATEST_VERSION}" | cut -d . -f 3)

    # Print the current/latest version and exit if requested
    echo "${BOLD}Current kernel version:${RST} ${CURRENT_VERSION}"
    echo
    echo "${BOLD}Latest kernel version:${RST} ${LATEST_VERSION}"
    if [[ ${PRINT_LATEST} ]]; then
        echo
        exit 0
    fi

    # UPDATE_MODES:
    # 0. Update one version
    # 1. Update to the latest version
    case ${UPDATE_MODE} in
        0)
            TARGET_SUBLEVEL=$((CURRENT_SUBLEVEL + 1))
            TARGET_VERSION=${CURRENT_MAJOR_VERSION}.${TARGET_SUBLEVEL} ;;
        1)
            TARGET_VERSION=${LATEST_VERSION} ;;
    esac

    # Make sure target version is between current version and latest version
    TARGET_SUBLEVEL=$(echo "${TARGET_VERSION}" | cut -d . -f 3)
    if [[ ${TARGET_SUBLEVEL} -le ${CURRENT_SUBLEVEL} ]]; then
        report_error "${TARGET_VERSION} is already present in ${CURRENT_VERSION}!\n"
    elif [[ ${TARGET_SUBLEVEL} -gt ${LATEST_SUBLEVEL} ]]; then
        report_error "${CURRENT_VERSION} is the latest!\n"
    fi

    RANGE=v${CURRENT_VERSION}..v${TARGET_VERSION}

    echo
    echo "${BOLD}Target kernel version:${RST} ${TARGET_VERSION}"
    echo
}


function update_to_target_version() {
    case ${UPDATE_METHOD} in
        "cherry-pick")
            if ! git cherry-pick "${RANGE}"; then
                report_error "Cherry-pick needs manual intervention! Resolve conflicts then run:

git add . && git cherry-pick --continue"
            else
                header "${TARGET_VERSION} PICKED CLEANLY!" "${GRN}"
            fi ;;

        "merge")
            if ! GIT_MERGE_VERBOSITY=1 git merge --no-edit v"${TARGET_VERSION}"; then
                report_error "Merge needs manual intervention!

Resolve conflicts then run git merge --continue!"
            else
                header "${TARGET_VERSION} MERGED CLEANLY!" "${GRN}"
            fi ;;
    esac
}


parse_parameters "$@"
update_remote
generate_versions
update_to_target_version
