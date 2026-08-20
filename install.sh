#!/bin/bash
set -euo pipefail

REPO="TelksBr/VeltrixUPGW"
PROJECT_NAME="VeltrixUPGW"
INSTALL_URL="https://raw.githubusercontent.com/TelksBr/VeltrixUPGW/main/install.sh"
MENU_URL="https://raw.githubusercontent.com/TelksBr/VeltrixUPGW/main/ugw.sh"
BINARY_NAME="udpgw"
MENU_NAME="ugw"
INSTALL_DIR="/usr/local/bin"
VERSION_FILE="/etc/udpgw-version"
MENU_REV_FILE="/etc/ugw-menu-revision"
INSTALLER_REV="3"
MENU_REV_EXPECTED="1"
DEFAULT_PORT=7400
BOX_WIDTH=51

TMP_DIR=""
INSTALL_COMPLETED=false
SERVICES_WERE_STOPPED=false
ACTIVE_UDPGW_SERVICES=()

MODE="install"
VERSION=""
ASSUME_YES=false
BINARY_ONLY=false
SKIP_MENU=false
SKIP_SERVICE=false
SKIP_HEADER=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}👉 $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}" >&2; }

usage() {
  cat <<EOF
Uso: $0 [opções]

Modos:
  (padrão)        Instalação (binário + menu + serviço padrão porta ${DEFAULT_PORT})
  --install       Mesmo que o padrão
  --update        Atualiza binário e menu (latest)
  --reinstall     Reinstala binário e menu

Opções:
  --latest, -L    Usa a release mais recente
  --version TAG   Versão específica (ex: v1.0.1)
  --binary-only   Instala/atualiza apenas o binário udpgw
  --no-menu       Não instala/atualiza o menu ugw
  --no-service    Não cria serviço systemd padrão na instalação inicial
  --yes, -y       Sem confirmações interativas
  --quiet, -q     Menos saída visual
  -h, --help      Exibe esta ajuda

Arquiteturas suportadas (detectadas automaticamente):
  amd64 (x86_64), arm64 (aarch64), armv7 (armv7l), 386 (i386/i686)

Exemplos:
  curl -fsSL "${INSTALL_URL}" | bash
  curl -fsSL "${INSTALL_URL}" | bash -s -- --update --yes
  curl -fsSL "${INSTALL_URL}" | bash -s -- --version v1.0.1 --yes
EOF
}

cleanup() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --install) MODE="install" ;;
    --update) MODE="update" ;;
    --reinstall) MODE="reinstall" ;;
    --latest | -L) VERSION="latest" ;;
    --version)
      shift
      VERSION="${1:-}"
      [[ -n "$VERSION" ]] || { log_error "Use --version TAG"; exit 1; }
      ;;
    --binary-only) BINARY_ONLY=true ;;
    --no-menu) SKIP_MENU=true ;;
    --no-service) SKIP_SERVICE=true ;;
    --yes | -y) ASSUME_YES=true ;;
    --quiet | -q) SKIP_HEADER=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    --) ;;
    *)
      log_error "Opção desconhecida: $1"
      usage
      exit 1
      ;;
    esac
    shift
  done

  case "$MODE" in
  update)
    [[ -z "$VERSION" ]] && VERSION="latest"
    ASSUME_YES=true
    ;;
  reinstall)
    BINARY_ONLY=false
    SKIP_MENU=false
    ;;
  esac
}

print_header() {
  [[ "$SKIP_HEADER" == true ]] && return 0
  local title="INSTALADOR ${PROJECT_NAME}"
  clear
  echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
  printf "${BLUE}║${NC}%-${BOX_WIDTH}s${BLUE}║${NC}\n" "$title"
  echo -e "${BLUE}╠═══════════════════════════════════════════════════╣${NC}"
  printf "${BLUE}║${NC}%-${BOX_WIDTH}s${BLUE}║${NC}\n" " Repositório: ${REPO}"
  printf "${BLUE}║${NC}%-${BOX_WIDTH}s${BLUE}║${NC}\n" " Modo:        ${MODE}"
  printf "${BLUE}║${NC}%-${BOX_WIDTH}s${BLUE}║${NC}\n" " Binário:     ${INSTALL_DIR}/${BINARY_NAME}"
  printf "${BLUE}║${NC}%-${BOX_WIDTH}s${BLUE}║${NC}\n" " Menu:        ${INSTALL_DIR}/${MENU_NAME}"
  printf "${BLUE}║${NC}%-${BOX_WIDTH}s${BLUE}║${NC}\n" " Revisão:     ${INSTALLER_REV}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
  echo
}

run_privileged() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    log_error "Privilégios de root necessários. Execute como root ou instale sudo."
    exit 1
  fi
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

has_command_path() {
  has_command "$1" || [[ -x "/usr/bin/$1" ]] || [[ -x "/bin/$1" ]]
}

has_checksum_command() {
  has_command_path sha256sum || has_command_path shasum
}

has_systemd() {
  has_command_path systemctl && [[ -d /run/systemd/system || -d /sys/fs/cgroup/systemd ]]
}

read_nonempty_lines() {
  local -n _target=$1
  local line
  _target=()
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    [[ -n "$line" ]] && _target+=("$line")
  done
}

get_missing_commands() {
  local missing=()
  has_command_path curl || missing+=("curl")
  has_checksum_command || missing+=("sha256sum")
  has_command_path ss || missing+=("ss")
  has_command_path systemctl || missing+=("systemctl")
  has_command_path journalctl || missing+=("journalctl")
  has_command_path bash || missing+=("bash")
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s\n' "${missing[@]}"
  fi
}

needs_sudo_install() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] && ! has_command_path sudo
}

ensure_sudo() {
  local pm

  needs_sudo_install || return 0

  pm=$(detect_package_manager)
  if [[ "$pm" == "unknown" ]]; then
    log_warn "sudo não encontrado e gerenciador de pacotes desconhecido — instale sudo manualmente."
    return 0
  fi

  log_info "sudo não encontrado — instalando via ${pm}..."
  if install_packages "$pm" sudo; then
    hash -r 2>/dev/null || true
    if has_command_path sudo; then
      log_success "sudo instalado."
    else
      log_warn "Pacote sudo instalado, mas comando ainda não disponível no PATH."
    fi
  else
    log_warn "Falha ao instalar sudo automaticamente."
  fi
}

commands_to_packages() {
  local pm="$1"
  shift
  local cmd packages=() pkg add_ca=false
  for cmd in "$@"; do
    cmd="${cmd//$'\r'/}"
    [[ -z "$cmd" ]] && continue
    case "$cmd" in
    curl)
      pkg="curl"
      add_ca=true
      ;;
    sha256sum) pkg="coreutils" ;;
    ss)
      case "$pm" in
      apk) pkg="iproute2" ;;
      *) pkg="iproute2" ;;
      esac
      ;;
    systemctl | journalctl)
      case "$pm" in
      apk) pkg="systemd" ;;
      *) pkg="systemd" ;;
      esac
      ;;
    bash) pkg="bash" ;;
    *) continue ;;
    esac
    [[ " ${packages[*]} " == *" $pkg "* ]] || packages+=("$pkg")
  done

  if [[ "$add_ca" == true ]]; then
    case "$pm" in
    apk)
      [[ " ${packages[*]} " == *" ca-certificates "* ]] || packages+=("ca-certificates")
      ;;
    pacman)
      [[ " ${packages[*]} " == *" ca-certificates "* ]] || packages+=("ca-certificates")
      ;;
    *)
      [[ " ${packages[*]} " == *" ca-certificates "* ]] || packages+=("ca-certificates")
      ;;
    esac
  fi

  if [[ ${#packages[@]} -gt 0 ]]; then
    printf '%s\n' "${packages[@]}"
  fi
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then echo apt
  elif command -v apk >/dev/null 2>&1; then echo apk
  elif command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  elif command -v pacman >/dev/null 2>&1; then echo pacman
  elif command -v zypper >/dev/null 2>&1; then echo zypper
  else echo unknown
  fi
}

install_packages() {
  local pm="$1"
  shift
  case "$pm" in
  apt)
    run_privileged apt-get update -qq
    run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    ;;
  apk) run_privileged apk add --no-cache "$@" ;;
  dnf) run_privileged dnf install -y "$@" ;;
  yum) run_privileged yum install -y "$@" ;;
  pacman) run_privileged pacman -Sy --noconfirm "$@" ;;
  zypper) run_privileged zypper install -y "$@" ;;
  *) return 1 ;;
  esac
}

ensure_dependencies() {
  local missing=() packages=() still_missing=() pm

  read_nonempty_lines missing < <(get_missing_commands)
  if [[ ${#missing[@]} -eq 0 ]]; then
    log_success "Dependências OK (curl, checksum, ss, systemd, bash)."
    return 0
  fi

  log_warn "Dependências ausentes: ${missing[*]}"
  pm=$(detect_package_manager)
  if [[ "$pm" == "unknown" ]]; then
    log_error "Gerenciador de pacotes não suportado."
    log_info "Instale manualmente: curl ca-certificates coreutils iproute2 systemd sudo bash"
    exit 1
  fi

  read_nonempty_lines packages < <(commands_to_packages "$pm" "${missing[@]}")
  if [[ ${#packages[@]} -eq 0 ]]; then
    log_error "Não foi possível mapear pacotes para: ${missing[*]}"
    exit 1
  fi

  log_info "Instalando dependências via ${pm}: ${packages[*]}"
  install_packages "$pm" "${packages[@]}" || {
    log_error "Falha ao instalar dependências."
    exit 1
  }

  hash -r 2>/dev/null || true
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

  has_command_path curl || still_missing+=("curl")
  has_checksum_command || still_missing+=("sha256sum")
  has_command_path ss || still_missing+=("ss")
  has_command_path bash || still_missing+=("bash")

  if [[ ${#still_missing[@]} -gt 0 ]]; then
    log_error "Ainda faltam dependências após instalação: ${still_missing[*]}"
    exit 1
  fi

  if ! has_command_path systemctl || ! has_command_path journalctl; then
    log_warn "systemd/journalctl indisponível — o menu e o serviço automático podem não funcionar."
    log_info "Use uma VPS com systemd (Debian/Ubuntu/CentOS) ou configure o udpgw manualmente."
  else
    log_success "Dependências OK (curl, checksum, ss, systemd, bash)."
  fi
}

detect_platform() {
  case "$(uname -s)" in
  Linux*) OS_NAME=linux ;;
  *)
    log_error "Sistema operacional não suportado (somente Linux)."
    exit 1
    ;;
  esac

  case "$(uname -m)" in
  x86_64) ARCH_NAME=amd64 ;;
  aarch64) ARCH_NAME=arm64 ;;
  armv7l) ARCH_NAME=armv7 ;;
  i386 | i686) ARCH_NAME=386 ;;
  *)
    log_error "Arquitetura não suportada: $(uname -m)"
    log_info "Suportadas: x86_64, aarch64, armv7l, i386/i686"
    exit 1
    ;;
  esac

  log_info "Plataforma detectada: ${OS_NAME}/${ARCH_NAME} ($(uname -m))"
}

download_file() {
  local url="$1"
  local output="$2"
  local http_status

  http_status=$(
    curl -fsSL \
      -H "Cache-Control: no-cache" \
      -H "Pragma: no-cache" \
      -w "%{http_code}" \
      -o "$output" \
      "$url" || true
  )
  if [[ "$http_status" != "200" || ! -s "$output" ]]; then
    log_error "Falha ao baixar: $url (HTTP ${http_status:-000})"
    exit 1
  fi
}

file_sha256() {
  local file="$1"
  if has_command sha256sum; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

extract_json_string_field() {
  local json="$1"
  local field="$2"
  echo "$json" \
    | grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" \
    | head -n1 \
    | sed -E "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/"
}

fetch_latest_release_tag() {
  local json tag
  json=$(curl -fsSL \
    -H "Cache-Control: no-cache" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases/latest" || true)
  tag=$(extract_json_string_field "$json" "tag_name")
  [[ -n "$tag" ]] || return 1
  echo "$tag"
}

normalize_version_tag() {
  local tag="$1"
  [[ -z "$tag" || "$tag" == "latest" ]] && return 1
  [[ "$tag" == v* ]] || tag="v${tag}"
  echo "$tag"
}

resolve_version_tag() {
  local requested="$1"
  local tag

  if [[ -z "$requested" || "$requested" == "latest" ]]; then
    tag=$(fetch_latest_release_tag || true)
    if [[ -z "$tag" ]]; then
      log_error "Não foi possível resolver a release latest em ${REPO}."
      exit 1
    fi
    echo "$tag"
    return 0
  fi

  normalize_version_tag "$requested"
}

get_installed_version() {
  if [[ -x "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    "${INSTALL_DIR}/${BINARY_NAME}" -version 2>/dev/null | tr -d 'v\r\n' || true
    return
  fi
  if [[ -f "$VERSION_FILE" ]]; then
    tr -d 'v\r\n' <"$VERSION_FILE"
  fi
}

show_current_installation() {
  local current
  current=$(get_installed_version || true)
  if [[ -n "$current" ]]; then
    log_info "Versão instalada: v${current}"
  else
    log_warn "Nenhuma instalação detectada em ${INSTALL_DIR}/${BINARY_NAME}"
  fi
}

verify_binary_checksum() {
  local filename="$1"
  local tag="$2"
  local sums_file="SHA256SUMS"
  local sums_url expected actual http_status

  tag=$(normalize_version_tag "$tag" || echo "$tag")
  sums_url="https://github.com/${REPO}/releases/download/${tag}/${sums_file}"

  http_status=$(curl -fsSL -w "%{http_code}" -o "$sums_file" "$sums_url" 2>/dev/null || true)
  if [[ "$http_status" != "200" ]]; then
    log_warn "SHA256SUMS não encontrado em ${tag}. Pulando verificação..."
    return 0
  fi

  expected=$(grep -E "[[:space:]]${filename}$" "$sums_file" | awk '{print $1}' | head -n1)
  if [[ -z "$expected" ]]; then
    log_warn "Entrada SHA256 não encontrada para ${filename}. Pulando verificação..."
    return 0
  fi

  actual=$(file_sha256 "$filename")
  if [[ "$actual" != "$expected" ]]; then
    log_error "Checksum inválido para ${filename}"
    log_info "Esperado: ${expected}"
    log_info "Obtido:   ${actual}"
    exit 1
  fi

  log_success "Integridade SHA256 verificada (${filename})."
}

capture_active_udpgw_services() {
  ACTIVE_UDPGW_SERVICES=()
  local f port sn
  for f in /etc/systemd/system/udpgw-*.service; do
    [[ -f "$f" ]] || continue
    port=$(basename "$f" .service | sed -n 's/^udpgw-\([0-9]\+\)$/\1/p')
    [[ -z "$port" ]] && continue
    sn="udpgw-${port}"
    if systemctl is-active --quiet "$sn" 2>/dev/null; then
      ACTIVE_UDPGW_SERVICES+=("$sn")
    fi
  done
  if [[ -f /etc/systemd/system/udpgw.service ]] && systemctl is-active --quiet udpgw 2>/dev/null; then
    ACTIVE_UDPGW_SERVICES+=("udpgw")
  fi
}

stop_udpgw_services() {
  [[ ${#ACTIVE_UDPGW_SERVICES[@]} -eq 0 ]] && return 0
  log_info "Parando serviços udpgw ativos..."
  local sn
  for sn in "${ACTIVE_UDPGW_SERVICES[@]}"; do
    run_privileged systemctl stop "$sn" 2>/dev/null || true
  done
  SERVICES_WERE_STOPPED=true
}

restart_udpgw_services() {
  [[ ${#ACTIVE_UDPGW_SERVICES[@]} -eq 0 ]] && return 0
  log_info "Reiniciando serviços udpgw..."
  local sn
  for sn in "${ACTIVE_UDPGW_SERVICES[@]}"; do
    run_privileged systemctl restart "$sn" 2>/dev/null || run_privileged systemctl start "$sn" 2>/dev/null || true
  done
}

download_and_install_binary() {
  local tag filename url

  tag=$(resolve_version_tag "$VERSION")
  VERSION="$tag"
  filename="udpgw-${OS_NAME}-${ARCH_NAME}"
  url="https://github.com/${REPO}/releases/download/${tag}/${filename}"

  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] || TMP_DIR=$(mktemp -d)
  cd "$TMP_DIR"

  log_info "Baixando binário: ${filename} (${tag})"
  log_info "URL: ${url}"
  download_file "$url" "$filename"
  verify_binary_checksum "$filename" "$tag"

  log_info "Instalando em ${INSTALL_DIR}/${BINARY_NAME}..."
  run_privileged install -m 755 "$filename" "${INSTALL_DIR}/${BINARY_NAME}"
  echo "${tag#v}" | run_privileged tee "$VERSION_FILE" >/dev/null
  log_success "Binário instalado: ${INSTALL_DIR}/${BINARY_NAME} (${tag})"
}

resolve_repo_main_sha() {
  local json sha
  json=$(curl -fsSL \
    -H "Cache-Control: no-cache" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/commits/main" || true)
  sha=$(extract_json_string_field "$json" "sha")
  [[ -n "$sha" && ${#sha} -ge 7 ]] || return 1
  echo "$sha"
}

install_menu_script() {
  if [[ "$BINARY_ONLY" == true || "$SKIP_MENU" == true ]]; then
    log_info "Pulando instalação do menu."
    return 0
  fi

  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] || TMP_DIR=$(mktemp -d)

  local menu_tmp="${TMP_DIR}/ugw.sh"
  local menu_dest="${INSTALL_DIR}/${MENU_NAME}"
  local menu_url menu_rev_found

  log_info "Baixando menu (ugw.sh)..."
  if menu_sha=$(resolve_repo_main_sha || true) && [[ -n "$menu_sha" ]]; then
    menu_url="https://raw.githubusercontent.com/${REPO}/${menu_sha}/ugw.sh"
    log_info "Commit main: ${menu_sha:0:12}"
  else
    menu_url="${MENU_URL}?$(date +%s)"
  fi

  download_file "$menu_url" "$menu_tmp"

  if ! head -n1 "$menu_tmp" | grep -qE '^#!'; then
    log_error "Menu baixado inválido (sem shebang)."
    exit 1
  fi

  menu_rev_found=$(
    grep -oE 'MENU_REV="[^"]+"' "$menu_tmp" 2>/dev/null \
      | head -n1 \
      | sed -E 's/MENU_REV="([^"]+)"/\1/' || true
  )

  run_privileged rm -f "$menu_dest"
  run_privileged install -m 755 "$menu_tmp" "$menu_dest"
  run_privileged ln -sfn "${MENU_NAME}" "${INSTALL_DIR}/udpgw-menu"
  hash -r 2>/dev/null || true

  echo "${menu_rev_found:-unknown}" | run_privileged tee "$MENU_REV_FILE" >/dev/null

  if [[ -n "$menu_rev_found" && -n "$MENU_REV_EXPECTED" && "$menu_rev_found" != "$MENU_REV_EXPECTED" ]]; then
    log_warn "Revisão do menu (${menu_rev_found}) difere da esperada (${MENU_REV_EXPECTED})."
  fi

  log_success "Menu instalado: ${menu_dest} (alias: udpgw-menu)"
}

has_any_udpgw_config() {
  [[ -f /etc/udpgw/config.conf ]] && return 0
  [[ -d /etc/udpgw/conf.d ]] && compgen -G "/etc/udpgw/conf.d/udpgw-*.conf" >/dev/null 2>&1 && return 0
  compgen -G "/etc/systemd/system/udpgw-*.service" >/dev/null 2>&1 && return 0
  [[ -f /etc/systemd/system/udpgw.service ]] && return 0
  return 1
}

setup_default_service() {
  if [[ "$SKIP_SERVICE" == true ]]; then
    log_info "Pulando criação de serviço padrão (--no-service)."
    return 0
  fi

  if has_any_udpgw_config; then
    log_info "Configuração udpgw existente detectada — serviço padrão não criado."
    return 0
  fi

  if ! has_systemd; then
    log_warn "systemd não detectado — configure o serviço manualmente."
    return 0
  fi

  local port="$DEFAULT_PORT"
  local config_dir="/etc/udpgw/conf.d"
  local config_file="${config_dir}/udpgw-${port}.conf"
  local service_file="/etc/systemd/system/udpgw-${port}.service"
  local metrics_listen="127.0.0.1:9091"

  log_info "Criando serviço padrão na porta TCP ${port}..."

  run_privileged mkdir -p /etc/udpgw "$config_dir"
  run_privileged tee "$config_file" >/dev/null <<EOF
PORT=${port}
LISTEN=0.0.0.0:${port}
DEBUG=false
METRICS_LISTEN=${metrics_listen}
MAX_FRAME=
WRITE_CHAN=
UDP_BIND=
UDP_RBUF=
UDP_WBUF=
MAP_TTL=
REAP_EVERY=
IDLE_TIMEOUT=
MAX_CLIENT_CONNS=
MAX_MAP_ENTRIES=
MAX_CLIENTS=
AUTO_RESTART_INTERVAL=
AUTO_RESTART_GRACE=
EOF

  run_privileged tee "$service_file" >/dev/null <<EOF
[Unit]
Description=BadVPN UDP Gateway (VeltrixUPGW) port ${port}
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=${INSTALL_DIR}/${BINARY_NAME} -listen 0.0.0.0:${port} -metrics-listen ${metrics_listen}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  run_privileged systemctl daemon-reload
  run_privileged systemctl enable "udpgw-${port}" >/dev/null 2>&1 || true
  run_privileged systemctl restart "udpgw-${port}" 2>/dev/null || run_privileged systemctl start "udpgw-${port}" 2>/dev/null || true

  if systemctl is-active --quiet "udpgw-${port}" 2>/dev/null; then
    log_success "Serviço udpgw-${port} ativo (TCP ${port}, metrics ${metrics_listen})."
  else
    log_warn "Serviço criado, mas pode não ter iniciado. Verifique: journalctl -u udpgw-${port} -n 30"
  fi
}

confirm_installation() {
  [[ "$ASSUME_YES" == true ]] && return 0
  if [[ ! -t 0 ]]; then
    log_info "Instalação via pipe (curl | bash) — continuando sem confirmação interativa."
    log_info "Use --yes explicitamente ou bash -s -- --yes para suprimir esta mensagem."
    return 0
  fi
  echo
  log_warn "Aguardando confirmação..."
  if [[ -r /dev/tty ]]; then
    read -rp "$(echo -e "${YELLOW}Continuar com a instalação? (s/N): ${NC}")" answer </dev/tty
  else
    read -rp "$(echo -e "${YELLOW}Continuar com a instalação? (s/N): ${NC}")" answer
  fi
  case "${answer,,}" in
  s | sim | y | yes) ;;
  *)
    log_warn "Instalação cancelada."
    exit 0
    ;;
  esac
}

print_finish_message() {
  echo
  log_success "Operação concluída!"
  log_info "Versão udpgw: ${VERSION}"
  if [[ "$BINARY_ONLY" != true && "$SKIP_MENU" != true ]]; then
    log_info "Abra o menu com: ${MENU_NAME}   (ou: udpgw-menu)"
    if [[ -f "$MENU_REV_FILE" ]]; then
      log_info "Revisão do menu: $(tr -d '\r\n' <"$MENU_REV_FILE")"
    fi
  fi
  echo
  log_info "Atualizar depois:"
  echo -e "  ${CYAN}curl -fsSL \"${INSTALL_URL}\" | bash -s -- --update --yes${NC}"
  echo
  log_info "Gerenciar portas, métricas e flags:"
  echo -e "  ${CYAN}sudo ${MENU_NAME}${NC}"
}

main() {
  parse_args "$@"
  print_header
  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && ! has_command_path sudo; then
    log_error "Execute como root na primeira instalação: curl -fsSL ... | bash"
    log_info "Depois de instalado, use: sudo ugw"
    exit 1
  fi
  ensure_dependencies
  ensure_sudo
  detect_platform
  show_current_installation

  if [[ -z "$VERSION" ]]; then
    VERSION="latest"
  fi

  if [[ "$MODE" == "install" && -z "$(get_installed_version || true)" ]]; then
    log_info "Nova instalação detectada."
  elif [[ "$MODE" == "update" ]]; then
    log_info "Modo atualização."
  fi

  confirm_installation

  capture_active_udpgw_services
  if [[ ${#ACTIVE_UDPGW_SERVICES[@]} -gt 0 ]]; then
    stop_udpgw_services
  fi

  download_and_install_binary
  install_menu_script

  if [[ "$MODE" == "install" ]]; then
    setup_default_service
  fi

  restart_udpgw_services
  INSTALL_COMPLETED=true
  print_finish_message
}

main "$@"
