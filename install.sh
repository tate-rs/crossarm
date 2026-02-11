#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly VERSION="2.0.0"

readonly DEFAULT_IMAGE_BASE="crossarm"
readonly DEFAULT_SCRIPT_BASE="${DEFAULT_IMAGE_BASE}"
readonly DEFAULT_ARCH="arm-linux-gnueabihf"
readonly DEFAULT_ARCH_VERSION="7.2-2017.11"
readonly DEFAULT_SUFFIX="arm"
readonly DEFAULT_HOST_PATH="${HOME}/.crossarm"
readonly DEFAULT_SCRIPT_PATH="${HOME}/.local/bin"
readonly CROSS_SYSROOT="/crossarm"

NO_CACHE=${NO_CACHE:-0}
UNINSTALL=${UNINSTALL:-0}
VERBOSE=${VERBOSE:-0}
DRY_RUN=${DRY_RUN:-0}
PRINT_VERSIONS=${PRINT_VERSIONS:-0}

LOG_DATE=no

ACTIONS=()

# default to no colour
RED='' GREEN='' ORANGE='' BLUE='' RESET=''

# Allow user to disable all colors by exporting NO_COLOR
# https://no-color.org/
# if user hasn’t disabled colour and we're on a TTY…
if [[ -z "${NO_COLOR-}" && -t 1 ]]; then
  # ask tput how many colours are supported
  if ncolors=$(tput colors 2>/dev/null) && (( ncolors >= 8 )); then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    ORANGE=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    RESET=$(tput sgr0)
  fi
fi

##########
# Logging
##########

function log {
    local color="${1:-}"
    local symbol="${2:-}"
    shift 2
    local message="$*"
    local current_date=''

    if [[ "$LOG_DATE" == "yes" ]]; then
        current_date="$(date +"%Y-%m-%d %T%z") "
    fi

    # %b tells printf to interpret backslash escapes in the arguments
    printf "[%s%b%s%b] %s\n" \
      "$current_date" \
      "$color"   "$symbol" \
      "$RESET" \
      "$message"
}

function err   { log "$RED"    "ERROR"   "$@" >&2; }
function warn  { log "$ORANGE" "WARNING" "$@" >&2; }
function succ  { log "$GREEN"  "SUCCESS" "$@";    }
function info  { log "$BLUE"   "INFO"    "$@";    }

##########
# Helpers
##########

# $1 = name of the var, $2 = default vlaue
function get_env() {
	local value=${!1:-$2}
	echo "${value}"
}

# $1 = name of the var
function get_required_env() {
	if [[ ! -v "$1" ]]; then
		err "Environment variable $1 is not set"
		exit 1
	fi
	
	echo "${!1}"
}

# $1 = name of the var, $2 = its value
function require_arg() {
    local name="${1:-}"
    local val="${2:-}"
    if [[ -z "$val" ]]; then
        err "Missing required argument: $name"
        print_help
        exit 1
    fi
}

# $1 = filename
function expect_file() {
    local file="${1:-}"
    if [[ ! -e "$file" ]]; then
        err "File does not exist: $file"
        exit 1
    fi
}

# $1 = program name
function expect_installed() {
    local prog="${1:-}"
    if ! command -v "$prog" >/dev/null 2>&1; then
        err "Required program not installed: $prog"
        exit 1
    fi
}

##################
# Usage & Version
##################

function print_help() {
    # print_arg <short> <long> <description>
    function print_arg() {
        local short="${1:-}"
        local long="${2:-}"
        local desc="${3:-}"
        local short_col="$short"

        if [[ -n "$short" && -n "$long" ]]; then
            short_col="${short},"
        fi

        printf "   %-5s %-30s - %s\n" "$short_col" "$long" "$desc"
    }

    printf "${BLUE}%s${RESET} <ARGS>\n\n" "$0"
    printf " Arguments:\n"
    print_arg "-h" "--help"                             "Prints this help"
    print_arg "-V"   "--version"                        "Show version and exit"
    print_arg "-n"   "--no-cache"                       "Build docker image without cache"
    print_arg "-u"   "--uninstall"                      "Uninstall the toolchain"
    print_arg "-a"   "--architecture ARCH"              "Set architecture. Default: ${DEFAULT_ARCH}"
    print_arg "-v"   "--architecture-version VERSION"   "Set architecture version. Default: ${DEFAULT_ARCH_VERSION}"
    print_arg ""     "--list-versions"                  "Print available toolchain versions"
    print_arg ""     "--launcher-path PATH"             "Set launcher install path. Default: ${DEFAULT_SCRIPT_PATH}"
    print_arg ""     "--sysroot-path PATH"              "Set sysroot install path. Default: ${DEFAULT_HOST_PATH}"
    print_arg ""     "--dry-run"                        "Dry run"
    print_arg "-s"   "--suffix NAME"                    "Custom script suffix (e.g. \"myname\" for crossarm-myname). Default: ${DEFAULT_SUFFIX}"
}

function print_version() {
    printf "%s$ v%s\n" "${0:-}" "$VERSION"
}
###################
# Argument Parsing
###################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -V|--version)
            print_version
            exit 0
            ;;
        -a|--architecture)
            require_arg "ARCH" "${2:-}"
            CROSS_ARCH="$2"
            shift 2
            ;;
        --launcher-path)
            require_arg "PATH" "${2:-}"
            CROSS_SCRIPT_PATH="$2"
            shift 2
            ;;
        --sysroot-path)
            require_arg "PATH" "${2:-}"
            CROSS_HOST_PATH="$2"
            shift 2
            ;;
        -v|--architecture-version)
            require_arg "VERSION" "${2:-}"
            CROSS_ARCH_VERSION="$2"
            shift 2
            ;;
        --list-versions)
            PRINT_VERSIONS=1
            shift 1
            ;;
        -u|--uninstall)
            UNINSTALL=1
            shift 1
            ;;
        --dry-run)
            DRY_RUN=1
            shift 1
            ;;
        -n|--no-cache)
            NO_CACHE=1
            shift 1
            ;;
        -s|--suffix)
            require_arg "NAME" "${2:-}"
            CROSS_SUFFIX="$2"
            shift 2
            ;;
        --) # explicit end of options
            shift
            break
            ;;
        -*)
            err "Unknown option: $1"
            print_help
            exit 1
            ;;
        *)  # no more options
            break
            ;;
    esac
done

# Any leftover positional arguments are errors
if (( $# > 0 )); then
    err "Unexpected arguments: $*"
    print_help
    exit 1
fi

# If no actions were queued, show help
# if (( ${#ACTIONS[@]} == 0 )); then
#     print_help
#     exit 0
# fi

############
# Variables
############

CROSS_ARCH=$(get_env "CROSS_ARCH" "${DEFAULT_ARCH}")
CROSS_ARCH_VERSION=$(get_env "CROSS_ARCH_VERSION" "${DEFAULT_ARCH_VERSION}")
CROSS_SUFFIX=$(get_env "CROSS_SUFFIX" "${DEFAULT_SUFFIX}")
CROSS_HOST_PATH=$(get_env CROSS_HOST_PATH "${DEFAULT_HOST_PATH}")
CROSS_SCRIPT_PATH=$(get_env CROSS_SCRIPT_PATH "${DEFAULT_SCRIPT_PATH}")

IMAGE_BASE=$(get_env "IMAGE_BASE" "${DEFAULT_IMAGE_BASE}")
SCRIPT_BASE=$(get_env "SCRIPT_BASE" "${DEFAULT_SCRIPT_BASE}")

readonly CROSS_ARCH \
            CROSS_SUFFIX \
            CROSS_HOST_PATH \
            CROSS_ARCH_VERSION \
            IMAGE_BASE \
            SCRIPT_BASE 

HOST_UID=$(get_env "HOST_UID" "$(id -u)")
HOST_GID=$(get_env "HOST_GID" "$(id -g)")

##########
# Actions
##########

##############
# HELPERS
##############

spinner_run() {
    local msg="$1"
    shift
    local cmd=("$@")

    if (( VERBOSE )); then
        "${cmd[@]}"
        return $?
    fi

    local spin_chars='⣾⣷⣯⣟⡿⢿⣻⣽'
    local tmp
    tmp=$(mktemp)

    # Run command in background and capture all output
    "${cmd[@]}" >"$tmp" 2>&1 &
    local pid=$!

    local i=0
    tput civis 2>/dev/null || true   # hide cursor if possible

    while kill -0 "$pid" 2>/dev/null; do
        local char=${spin_chars:i++%${#spin_chars}:1}
        printf "\r${BLUE}%s${RESET} %s" "$char" "$msg"
        sleep 0.08
    done

    wait "$pid"
    local status=$?

    printf "\r"                     # clear line
    tput cnorm 2>/dev/null || true  # show cursor

    if [ $status -ne 0 ]; then
        err "$msg (exit $status)"
        echo "----- Output -----"
        cat "$tmp"
        echo "------------------"
    else
        succ "$msg"
    fi

    rm -f "$tmp"
    return $status
}

ask_yes_no() {
    local prompt="$1"
    local default=${2:-"-"}   # y / n / empty

    local choice
    local suffix

    case "$default" in
        y|Y) suffix="[Y/n]" ;;
        n|N) suffix="[y/N]" ;;
        *)   suffix="[y/n]" ;;
    esac

    while true; do
        read -r -p "$prompt $suffix: " choice
        choice=${choice:-$default}

        case "$choice" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No)   return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

function exec_cmd() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf -v cmd_str "%q " "$@"
        warn "DRY RUN: $cmd_str" 
    else
        "${@}"
    fi
}

function image_name() {
    echo "${IMAGE_BASE}"
}

function sysroot_name() {
    echo "${IMAGE_BASE}-${CROSS_SUFFIX}"
}

function script_name() {
    echo "${IMAGE_BASE}-${CROSS_SUFFIX}"
}

function shared_volume_path() {
    echo "${CROSS_HOST_PATH}/$(sysroot_name)"
}

# $1 - Tar file
function get_tar_toplevel_dir () {
    local old
    # capture current pipefail setting
    old=$(set +o | grep -E 'pipefail')   
    set +o pipefail
    tar tf "$1" | head -1 | cut -d/ -f1
    # restore
    eval "$old"                   
}

function ensure_host_path() {
    if [ ! -d "${CROSS_HOST_PATH}" ]; then
        info "Sysroot host path doesn't exist, creating..."
        exec_cmd mkdir -p "${CROSS_HOST_PATH}"
    fi
}

##############
# FETCHING
##############

# $1 - Toolchain folder
function install_toolchain() {
    ensure_host_path
    info "Installing toolchain to '$(shared_volume_path)'"
    exec_cmd mv -f "${1}" "$(shared_volume_path)" 
    info "Setting owner '${HOST_UID}:${HOST_GID}' to the '$(shared_volume_path)'"
    exec_cmd chown -R "${HOST_UID}:${HOST_GID}" "$(shared_volume_path)" 
}

function print_linaro_versions() {

    # $@ - Version list
    function print_versions() {
        echo "Available versions for ${BLUE}${CROSS_ARCH}${RESET}:"

        for v in "$@"; do
            echo "- $v"
        done
    }

    case "${CROSS_ARCH}" in
        arm-linux-gnueabihf)
            print_versions \
                "7.2-2017.11"
            ;;
        *) 
            err "Invalid architecture '${CROSS_ARCH}'"
            exit 1
            ;;
    esac
}

# $1 - Download path
function install_linaro_toolchain() {

    if [ -d "$(shared_volume_path)" ]; then
        warn "Toolchain already exists in $(shared_volume_path)"
        if ! ask_yes_no "Do you want to replace the toolchain?"; then
            err "Installation has been aborted"
            exit 1
        else
            exec_cmd rm -rf "$(shared_volume_path)"
        fi
    fi

    # $1 - File
    function get_download_url() {
        echo "https://releases.linaro.org/components/toolchain/binaries/${CROSS_ARCH_VERSION}/${CROSS_ARCH}/${1}"
    }

    local CWD
    CWD="$(pwd)"

    exec_cmd cd "${1}"

    local DOWNLOAD_URL
    case "${CROSS_ARCH}" in
        arm-linux-gnueabihf)
            case "${CROSS_ARCH_VERSION}" in
                7.2-2017.11)
                    DOWNLOAD_URL="$(get_download_url gcc-linaro-7.2.1-2017.11-x86_64_arm-linux-gnueabihf.tar.xz)"
                    ;;
                *) 
                    err "Invalid architecture version '${CROSS_ARCH_VERSION}'"
                    exit 1
                    ;;
            esac
            ;;
        *) 
            err "Invalid architecture '${CROSS_ARCH}'"
            exit 1
            ;;
    esac

    local TOOLCHAIN_DIR

    # info "Downloading toolchain"
    exec_cmd spinner_run "Downloading toolchain" wget -O toolchain.tar.xz "${DOWNLOAD_URL}"
    TOOLCHAIN_DIR=$(get_tar_toplevel_dir "toolchain.tar.xz")

    info "Extracting toolchain"
    exec_cmd tar xvf toolchain.tar.xz &> /dev/null
    exec_cmd rm -rf toolchain.tar.xz &> /dev/null

    install_toolchain "${TOOLCHAIN_DIR}"

    exec_cmd cd "${CWD}"
}

function finalize_toolchain() {
    info "Setting up toolchain.cmake"
    exec_cmd cp "toolchain.cmake" "$(shared_volume_path)/."
    exec_cmd sed -i "s/toolchain_here/${CROSS_ARCH}-/" "$(shared_volume_path)/toolchain.cmake"
    succ "toolchain.cmake has been set up"
}

##############
# BUILDING
##############

function build_docker() {
    local BUILD_ARGS=()
    (( NO_CACHE )) && BUILD_ARGS+=(--no-cache)
    BUILD_ARGS+=(
        -t "$(image_name)"
        --build-arg "HOST_UID=${HOST_UID}"
        --build-arg "HOST_GID=${HOST_GID}"
        --build-arg "CROSS_SYSROOT_DIR=${CROSS_SYSROOT}"
        --build-arg "CROSS_ARCH=${CROSS_ARCH}"
        .
    )

    local DOCKER_BUILD_CMD
    if docker buildx version &>/dev/null; then
        DOCKER_BUILD_CMD=(docker buildx build)
    else
        DOCKER_BUILD_CMD=(docker build)
    fi

    info "Building docker image $(image_name)"
    exec_cmd spinner_run "Building image" "${DOCKER_BUILD_CMD[@]}" "${BUILD_ARGS[@]}"
    succ "Docker image has been successfully built"
}

function install_launcher() {
    local LAUNCHER_PATH
    LAUNCHER_PATH="${CROSS_SCRIPT_PATH}/$(script_name)"

    info "Creating launcher $(script_name)"
    exec_cmd cat > "${LAUNCHER_PATH}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Defaults
SRC_DIR="\$(pwd)"
CMD=""

print_help() {
  cat <<EOH
Usage: \${0##*/} [path] [-c command]

Arguments:
  path        Directory to mount into /project
  -c CMD      Execute CMD inside the container
  -h, --help  Show this help
EOH
}

# Parse args
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -h|--help) print_help; exit 0 ;;
    -c) shift; CMD="\$1"; shift ;;
    *) SRC_DIR="\$1"; shift ;;
  esac
done

# Resolve to absolute path
[[ "\${SRC_DIR}" != /* ]] && SRC_DIR="\$(pwd)/\${SRC_DIR}"

# Base docker command
DOCKER_CMD=(
  docker run --rm -it
  -v "\${SRC_DIR}:/project"
  -v "$(shared_volume_path):${CROSS_SYSROOT}"
  "$(image_name)"
)

# Execute
if [[ -n "\$CMD" ]]; then
  "\${DOCKER_CMD[@]}" "\$CMD"
else
  "\${DOCKER_CMD[@]}"
fi
EOF

    exec_cmd chmod u+x "${LAUNCHER_PATH}"

    succ "Installed launcher at ${LAUNCHER_PATH}"

}

#######
# Main
#######

echo "--------------------------------------------------"
echo "-------------------- CROSSARM --------------------"
echo "--------------------------------------------------"
printf "\n"
printf "Using:\n"
printf " - Architecture: ${BLUE}${CROSS_ARCH}${RESET}\n"
printf " - Toolchain version: ${BLUE}${CROSS_ARCH_VERSION}${RESET}\n"
printf " - Suffix: ${BLUE}${CROSS_SUFFIX}${RESET}\n"
printf " - Docker image: ${BLUE}$(image_name)${RESET}\n"
printf " - Launcher: ${BLUE}$(script_name)${RESET}\n"
printf " - Sysroot path: ${BLUE}$(shared_volume_path)${RESET}\n"
printf "\n"
echo "--------------------------------------------------"
printf "\n"

if (( PRINT_VERSIONS )); then
    print_linaro_versions
    exit 0
fi

expect_installed "docker"
expect_installed "wget"
expect_installed "tar"
expect_installed "sed"

if (( UNINSTALL )); then
    if [ ! -d "$(shared_volume_path)" ]; then
        err "Toolchain $(script_name) is not installed"
        exit 1
    fi

    info "Uninstalling sysroot '$(shared_volume_path)'"
    exec_cmd rm -r "$(shared_volume_path)"
    succ "Sysroot has been successfully uninstalled"

    info "Uninstalling launcher '${CROSS_SCRIPT_PATH}/$(script_name)'"
    exec_cmd rm -r "${CROSS_SCRIPT_PATH}/$(script_name)"
    succ "Launcher has been successfully uninstalled"

    info "You need to uninstall the image manually by running \`docker rmi $(image_name)\`"
    exit 0
fi

info "Installing toolchain"
install_linaro_toolchain "."
finalize_toolchain
build_docker
install_launcher

printf "\n"
succ "Setup complete! Run '$(script_name)' to enter the cross-compile environment."
