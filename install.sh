#!/usr/bin/env bash
# Standalone installer for prebuilt LanBuffer binaries (macOS/Linux).
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[=>]${NC} $*"; }

usage() {
  cat <<'EOF'
LanBuffer installer (downloads prebuilt binaries)

Usage:
  install.sh [--version vX.Y.Z] [--repo owner/lanbuffer-release]
             [--install-dir DIR] [--config-dir DIR]
             [--no-verify] [--uninstall]

Defaults:
  --repo         LANBUFFER_RELEASE_REPO or "YOUR_ORG/lanbuffer-release"
  --install-dir  ~/.local/bin
  --config-dir   ~/.config/lanbuffer

Examples:
  ./install.sh
  ./install.sh --version v1.0.2
  ./install.sh --repo acme/lanbuffer-release
  ./install.sh --uninstall
EOF
}

REPO_DEFAULT="duanfuxiang0/lanbuffer-release"
REPO="${LANBUFFER_RELEASE_REPO:-$REPO_DEFAULT}"
VERSION=""
INSTALL_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/lanbuffer"
NO_VERIFY=false
ACTION="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --config-dir) CONFIG_DIR="${2:-}"; shift 2 ;;
    --no-verify) NO_VERIFY=true; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage; exit 2 ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log_error "Missing required command: $1"; exit 1; }
}

detect_target() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux) os="unknown-linux-musl" ;;
    Darwin) os="apple-darwin" ;;
    *) log_error "Unsupported OS: $os"; exit 1 ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    *) log_error "Unsupported arch: $arch"; exit 1 ;;
  esac

  echo "${arch}-${os}"
}

github_api() {
  local url="$1"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" "$url"
  else
    curl -fsSL "$url"
  fi
}

resolve_latest_version() {
  require_cmd curl
  require_cmd sed
  require_cmd grep

  local json tag
  json="$(github_api "https://api.github.com/repos/${REPO}/releases/latest")"
  tag="$(echo "$json" | grep -Eo '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)".*/\1/')"
  if [[ -z "${tag:-}" ]]; then
    log_error "Failed to resolve latest version from GitHub API for ${REPO}"
    exit 1
  fi
  echo "$tag"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    log_error "sha256sum/shasum not found"
    exit 1
  fi
}

install_config_templates() {
  mkdir -p "$CONFIG_DIR"

  cat > "${CONFIG_DIR}/lanbuffer.toml.example" << 'TOML'
# LanBuffer Configuration
# Copy this file to lanbuffer.toml and edit the values.
#
# Environment variables are supported: ${VAR_NAME}
# All referenced variables must be set when lanbuffer starts.

[cache]
dir = "${HOME}/.cache/lanbuffer"
disk_size_gb = 10.0
memory_size_gb = 1.0

[storage]
url = "${STORAGE_URL}"
encryption_password = "${LANBUFFER_PASSWORD}"

[filesystem]
compression = "lz4"

[servers.nfs]
addresses = ["127.0.0.1:2049"]

[servers.table]
addresses = ["127.0.0.1:7001"]

[servers.kv]
addresses = ["127.0.0.1:7002"]

[aws]
access_key_id = "${AWS_ACCESS_KEY_ID}"
secret_access_key = "${AWS_SECRET_ACCESS_KEY}"
TOML

  cat > "${CONFIG_DIR}/.env.example" << 'ENV'
LANBUFFER_PASSWORD=change_me
STORAGE_URL=s3://your-bucket/lanbuffer-data

AWS_ACCESS_KEY_ID=change_me
AWS_SECRET_ACCESS_KEY=change_me

# Optional
# RUST_LOG=info
ENV

  cat > "${CONFIG_DIR}/run.sh" << 'RUNSH'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/lanbuffer.toml"
ENV_FILE="${SCRIPT_DIR}/.env"

load_env() {
  [[ -f "$1" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      value="${value#\"}" ; value="${value%\"}"
      value="${value#\'}" ; value="${value%\'}"
      [[ -z "${!key:-}" ]] && export "$key=$value"
    fi
  done < "$1"
}

load_env "$ENV_FILE"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Config not found: $CONFIG_FILE" >&2
  echo "  cp lanbuffer.toml.example lanbuffer.toml" >&2
  echo "  cp .env.example .env" >&2
  exit 1
fi

exec lanbuffer run --config "$CONFIG_FILE"
RUNSH
  chmod +x "${CONFIG_DIR}/run.sh"
}

check_path_hint() {
  if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    log_warn "${INSTALL_DIR} is not in your PATH"
    log_warn "Add: export PATH=\"${INSTALL_DIR}:\$PATH\""
  fi
}

do_uninstall() {
  log_step "Uninstalling..."
  rm -f "${INSTALL_DIR}/lanbuffer" || true
  log_info "Removed ${INSTALL_DIR}/lanbuffer"
  log_warn "Config is kept at ${CONFIG_DIR} (remove manually if desired)"
}

do_install() {
  require_cmd curl
  require_cmd tar

  # If you fork, pass --repo or set LANBUFFER_RELEASE_REPO.

  if [[ -z "${VERSION:-}" ]]; then
    log_step "Resolving latest version from ${REPO}..."
    VERSION="$(resolve_latest_version)"
  fi

  local target asset base_url tmp_dir archive sha_file
  target="$(detect_target)"
  asset="lanbuffer-${VERSION}-${target}.tar.gz"
  base_url="https://github.com/${REPO}/releases/download/${VERSION}"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  archive="${tmp_dir}/${asset}"
  sha_file="${archive}.sha256"

  log_step "Downloading ${asset}..."
  curl -fsSL -o "$archive" "${base_url}/${asset}"

  if ! $NO_VERIFY; then
    log_step "Verifying checksum..."
    if curl -fsSL -o "$sha_file" "${base_url}/${asset}.sha256"; then
      expected="$(awk '{print $1}' "$sha_file" | head -n1)"
      actual="$(sha256_file "$archive")"
      if [[ -z "${expected:-}" || "$expected" != "$actual" ]]; then
        log_error "Checksum mismatch for ${asset}"
        log_error "Expected: ${expected:-<empty>}"
        log_error "Actual:   ${actual}"
        exit 1
      fi
    else
      log_warn "Checksum file not found; skipping verification"
    fi
  fi

  log_step "Installing binary..."
  mkdir -p "$INSTALL_DIR"
  tar -C "$tmp_dir" -xzf "$archive"
  install -m 755 "${tmp_dir}/lanbuffer" "${INSTALL_DIR}/lanbuffer"

  log_step "Installing config templates..."
  install_config_templates

  check_path_hint

  echo ""
  log_info "Installed:"
  echo "  Binary:  ${INSTALL_DIR}/lanbuffer"
  echo "  Config:  ${CONFIG_DIR}"
  echo ""
  echo "Quick start:"
  echo "  cd ${CONFIG_DIR}"
  echo "  cp lanbuffer.toml.example lanbuffer.toml"
  echo "  cp .env.example .env"
  echo "  ./run.sh"
}

case "$ACTION" in
  uninstall) do_uninstall ;;
  install) do_install ;;
  *) log_error "Unknown action: $ACTION"; exit 2 ;;
esac
