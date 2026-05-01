#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_OWNER="fcanlnony"
REPO_NAME="Entrance"
REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"
LATEST_RELEASE_API="https://api.github.com/repos/${REPO_SLUG}/releases/latest"

INSTALL_DIR="${HOME}/.entrance"
DATA_DIR="${INSTALL_DIR}/.data"
DEFAULT_SERVICE_NAME="entrance.service"
NOCORS_SERVICE_NAME="entrance-nocors.service"
DESKTOP_NAME="entrance.desktop"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
DESKTOP_DIR="${HOME}/.local/share/applications"
DEFAULT_SERVICE_TEMPLATE="${SCRIPT_DIR}/service/${DEFAULT_SERVICE_NAME}"
NOCORS_SERVICE_TEMPLATE="${SCRIPT_DIR}/service/${NOCORS_SERVICE_NAME}"
DESKTOP_TEMPLATE="${SCRIPT_DIR}/service/${DESKTOP_NAME}"
DEFAULT_INSTALLED_SERVICE="${SYSTEMD_USER_DIR}/${DEFAULT_SERVICE_NAME}"
NOCORS_INSTALLED_SERVICE="${SYSTEMD_USER_DIR}/${NOCORS_SERVICE_NAME}"
INSTALLED_DESKTOP="${DESKTOP_DIR}/${DESKTOP_NAME}"
APP_URL="http://localhost:3000"
COMMAND="install"
ENABLE_NOCORS=0

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$cmd" >&2
        exit 1
    fi
}

json_string_field() {
    local json="$1"
    local field="$2"
    printf '%s\n' "$json" | sed -n "s/.*\"${field}\": \"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

latest_release_json() {
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${LATEST_RELEASE_API}"
}

latest_archive_url() {
    local json="$1"
    local tar_xz_url

    tar_xz_url="$(printf '%s\n' "$json" | sed -n 's/.*"browser_download_url": "\(.*\.tar\.xz\)".*/\1/p' | head -n 1)"
    if [[ -n "${tar_xz_url}" ]]; then
        printf '%s\n' "${tar_xz_url}"
        return 0
    fi

    json_string_field "$json" "tarball_url"
}

latest_archive_filename() {
    local version="$1"
    local archive_url="$2"

    if [[ "${archive_url}" == *.tar.xz ]]; then
        basename "${archive_url}"
        return 0
    fi

    printf '%s-%s.tar.gz\n' "${REPO_NAME}" "${version}"
}

download_release_archive() {
    local archive_url="$1"
    local archive_path="$2"

    curl -fL "${archive_url}" -o "${archive_path}"
}

cleanup_install_dir() {
    mkdir -p "${INSTALL_DIR}"

    while IFS= read -r entry; do
        rm -rf "${entry}"
    done < <(find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 ! -name '.data' -print)
}

extract_release_archive() {
    local archive_path="$1"
    local temp_extract_dir="$2"
    local extracted_root

    mkdir -p "${temp_extract_dir}"
    tar -xf "${archive_path}" -C "${temp_extract_dir}"
    extracted_root="$(find "${temp_extract_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [[ -z "${extracted_root}" ]]; then
        printf 'Unable to find extracted release directory.\n' >&2
        exit 1
    fi

    cleanup_install_dir
    cp -a "${extracted_root}/." "${INSTALL_DIR}/"
}

ensure_runtime_data() {
    mkdir -p "${DATA_DIR}"
    if [[ ! -f "${DATA_DIR}/auth_secret" ]]; then
        openssl rand -base64 32 > "${DATA_DIR}/auth_secret"
        chmod 600 "${DATA_DIR}/auth_secret"
    fi
}

install_dependencies() {
    if [[ -f "${INSTALL_DIR}/package-lock.json" ]]; then
        (cd "${INSTALL_DIR}" && npm ci --omit=dev)
        return 0
    fi

    (cd "${INSTALL_DIR}" && npm install --omit=dev)
}

render_template() {
    local src="$1"
    local dest="$2"
    local escaped_install_dir escaped_path escaped_icon_path

    escaped_install_dir="$(printf '%s' "${INSTALL_DIR}" | sed 's/[&|]/\\&/g')"
    escaped_path="$(printf '%s' "${PATH}" | sed 's/[&|]/\\&/g')"
    escaped_icon_path="$(printf '%s' "${INSTALL_DIR}/public/logo.png" | sed 's/[&|]/\\&/g')"

    sed \
        -e "s|@INSTALL_DIR@|${escaped_install_dir}|g" \
        -e "s|@PATH_VALUE@|${escaped_path}|g" \
        -e "s|@ICON_PATH@|${escaped_icon_path}|g" \
        "${src}" > "${dest}"
}

resolve_enabled_service_name() {
    if [[ "${ENABLE_NOCORS}" -eq 1 ]]; then
        printf '%s\n' "${NOCORS_SERVICE_NAME}"
        return 0
    fi

    printf '%s\n' "${DEFAULT_SERVICE_NAME}"
}

install_services() {
    local enabled_service_name="$1"

    mkdir -p "${SYSTEMD_USER_DIR}"
    render_template "${DEFAULT_SERVICE_TEMPLATE}" "${DEFAULT_INSTALLED_SERVICE}"
    render_template "${NOCORS_SERVICE_TEMPLATE}" "${NOCORS_INSTALLED_SERVICE}"

    systemctl --user daemon-reload

    systemctl --user disable --now "${DEFAULT_SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl --user disable --now "${NOCORS_SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl --user enable --now "${enabled_service_name}"
}

install_desktop_entry() {
    mkdir -p "${DESKTOP_DIR}"
    render_template "${DESKTOP_TEMPLATE}" "${INSTALLED_DESKTOP}"
    chmod 644 "${INSTALLED_DESKTOP}"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
    fi
}

stop_services_if_present() {
    systemctl --user disable --now "${DEFAULT_SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl --user disable --now "${NOCORS_SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl --user daemon-reload
}

uninstall_app() {
    stop_services_if_present
    rm -f "${DEFAULT_INSTALLED_SERVICE}"
    rm -f "${NOCORS_INSTALLED_SERVICE}"
    rm -f "${INSTALLED_DESKTOP}"
    rm -rf "${INSTALL_DIR}"

    systemctl --user daemon-reload || true
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
    fi

    printf 'Removed %s, %s, %s, and %s.\n' \
        "${INSTALL_DIR}" \
        "${DEFAULT_INSTALLED_SERVICE}" \
        "${NOCORS_INSTALLED_SERVICE}" \
        "${INSTALLED_DESKTOP}"
}

install_app() {
    local enabled_service_name
    local release_json version release_page archive_url archive_name
    local temp_dir archive_path extract_dir

    enabled_service_name="$(resolve_enabled_service_name)"

    release_json="$(latest_release_json)"
    version="$(json_string_field "${release_json}" "tag_name")"
    release_page="$(json_string_field "${release_json}" "html_url")"
    archive_url="$(latest_archive_url "${release_json}")"

    if [[ -z "${version}" || -z "${archive_url}" ]]; then
        printf 'Unable to determine the latest Entrance release.\n' >&2
        exit 1
    fi

    archive_name="$(latest_archive_filename "${version}" "${archive_url}")"
    temp_dir="$(mktemp -d)"
    archive_path="${temp_dir}/${archive_name}"
    extract_dir="${temp_dir}/extract"

    printf 'Installing %s release %s\n' "${REPO_NAME}" "${version}"
    printf 'Release page: %s\n' "${release_page}"
    printf 'Archive URL: %s\n' "${archive_url}"

    download_release_archive "${archive_url}" "${archive_path}"
    extract_release_archive "${archive_path}" "${extract_dir}"
    ensure_runtime_data
    install_dependencies
    install_services "${enabled_service_name}"
    install_desktop_entry

    rm -rf "${temp_dir}"

    printf 'Installed to %s\n' "${INSTALL_DIR}"
    printf 'Installed services: %s, %s\n' "${DEFAULT_INSTALLED_SERVICE}" "${NOCORS_INSTALLED_SERVICE}"
    printf 'Enabled service: systemctl --user status %s\n' "${enabled_service_name}"
    printf 'Desktop entry: %s\n' "${INSTALLED_DESKTOP}"
    printf 'Open: %s\n' "${APP_URL}"
}

usage() {
    cat <<'EOF'
Usage:
  ./install.sh [install] [--nocors]
  ./install.sh uninstall

Options:
  --nocors    Install both services, but enable entrance-nocors.service
EOF
}

parse_args() {
    local command_seen=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|uninstall)
                if [[ "${command_seen}" -eq 1 ]]; then
                    printf 'Only one command may be specified.\n' >&2
                    usage
                    exit 1
                fi
                COMMAND="$1"
                command_seen=1
                ;;
            --nocors)
                ENABLE_NOCORS=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown argument: %s\n' "$1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"

    if [[ ! -f "${DEFAULT_SERVICE_TEMPLATE}" ]]; then
        printf 'Missing service template: %s\n' "${DEFAULT_SERVICE_TEMPLATE}" >&2
        exit 1
    fi

    if [[ ! -f "${NOCORS_SERVICE_TEMPLATE}" ]]; then
        printf 'Missing service template: %s\n' "${NOCORS_SERVICE_TEMPLATE}" >&2
        exit 1
    fi

    if [[ ! -f "${DESKTOP_TEMPLATE}" ]]; then
        printf 'Missing desktop template: %s\n' "${DESKTOP_TEMPLATE}" >&2
        exit 1
    fi

    case "${COMMAND}" in
        install)
            require_cmd bash
            require_cmd curl
            require_cmd tar
            require_cmd openssl
            require_cmd npm
            require_cmd systemctl
            require_cmd sed
            require_cmd find
            require_cmd cp
            require_cmd mktemp
            install_app
            ;;
        uninstall)
            require_cmd bash
            require_cmd systemctl
            uninstall_app
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
