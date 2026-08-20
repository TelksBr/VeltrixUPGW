#!/bin/bash

readonly PROJECT_NAME="VeltrixUPGW"
readonly MENU_BOX_MIN=34
readonly MENU_BOX_MAX=56
readonly MENU_REV="1"
readonly INSTALL_URL="https://raw.githubusercontent.com/TelksBr/VeltrixUPGW/main/install.sh"
readonly MENU_BIN="/usr/local/bin/ugw"
readonly UDPGW_VERSION_FILE="/etc/udpgw-version"
readonly UDPGW_REPO="TelksBr/VeltrixUPGW"

MENU_BOX_WIDTH=$MENU_BOX_MAX

UDPGW_BIN="/usr/local/bin/udpgw"
UDPGW_CONFIG_DIR="/etc/udpgw/conf.d"
UDPGW_CONFIG_FILE="/etc/udpgw/config.conf"
UDPGW_SERVICE_PREFIX="udpgw"
UDPGW_SERVICE_NAME="udpgw"
UDPGW_DEFAULT_PORT=7400
UDPGW_DEFAULT_LISTEN="0.0.0.0:7400"
UDPGW_METRICS_BASE=9091

MIN_PORT=1
MAX_PORT=65535

RED=$'\033[1;31m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
PURPLE=$'\033[1;35m'
CYAN=$'\033[1;36m'
WHITE=$'\033[1;37m'
GRAY=$'\033[1;90m'
BG_BLUE=$'\033[44m'
BG_GREEN=$'\033[42m'
BG_RED=$'\033[41m'
BG_GRAY=$'\033[100m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

strip_ansi() {
    # Remove códigos ANSI reais (\x1b) e literais \\033 — sem depender de python3.
    printf '%s' "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\\033\[[0-9;]*[a-zA-Z]//g'
}

visible_len() {
    local plain
    plain=$(strip_ansi "$1")
    printf '%s' "${#plain}"
}

detect_term_cols() {
    local cols="${COLUMNS:-}"
    if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
        cols=$(stty size 2>/dev/null | awk '{print $2}')
    fi
    if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then
        cols=$(tput cols 2>/dev/null || true)
    fi
    if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
        cols=80
    fi
    printf '%s' "$cols"
}

# Ajusta a caixa ao terminal (mobile ~40 cols; desktop até MENU_BOX_MAX).
refresh_menu_layout() {
    local cols inner
    cols=$(detect_term_cols)
    # 2 chars das bordas ║ … ║; 1 de folga evita wrap em alguns clientes SSH
    inner=$((cols - 3))
    if ((inner > MENU_BOX_MAX)); then
        inner=$MENU_BOX_MAX
    elif ((inner < MENU_BOX_MIN)); then
        # Em telas bem estreitas, espreme até o mínimo absoluto
        if ((cols - 2 >= 28)); then
            inner=$((cols - 2))
        else
            inner=28
        fi
    fi
    MENU_BOX_WIDTH=$inner
}

is_narrow_menu() {
    ((MENU_BOX_WIDTH < 46))
}

# Emojis (✅❌) viram "?" no Termius/mobile — usar ASCII colorido.
mark_ok() { printf '%s' "${GREEN}OK${RESET}"; }
mark_fail() { printf '%s' "${RED}X${RESET}"; }
mark_online() { printf '%s' "${GREEN}ON${RESET}"; }
mark_offline() { printf '%s' "${RED}OFF${RESET}"; }

truncate_visible() {
    local text="$1"
    local max="$2"
    local plain cut
    plain=$(strip_ansi "$text")
    if ((${#plain} <= max)); then
        printf '%s' "$text"
        return
    fi
    cut=$((max - 1))
    ((cut < 1)) && cut=1
    # "..." ASCII — reticência unicode quebra em alguns terminais mobile
    printf '%s...' "${plain:0:cut}"
}

# Caixas em ASCII puro — bordas Unicode (═║╔╗) viram "?" em Termius/mobile.
print_box_rule() {
    local left="$1"
    local right="$2"
    local fill
    fill=$(printf '%*s' "$MENU_BOX_WIDTH" "" | tr ' ' '-')
    printf '%b%s%b\n' "${BLUE}${left}" "$fill" "${right}${RESET}"
}

print_box_open() {
    print_box_rule "+" "+"
}

print_box_divider() {
    print_box_rule "+" "+"
}

print_box_close() {
    print_box_rule "+" "+"
}

print_box_line() {
    local content="$1"
    local inner_width="${2:-$MENU_BOX_WIDTH}"
    local len pad
    len=$(visible_len "$content")
    [[ "$len" =~ ^[0-9]+$ ]] || len=0
    if ((len > inner_width)); then
        content=$(truncate_visible "$content" "$inner_width")
        len=$(visible_len "$content")
    fi
    pad=$((inner_width - len))
    ((pad < 0)) && pad=0
    printf '%b' "${BLUE}|${RESET}${content}"
    printf '%*s' "$pad" ""
    printf '%b\n' "${BLUE}|${RESET}"
}

print_box_heading() {
    local text="$1"
    local color="${2:-$WHITE}"
    local plain len left right
    plain=$(strip_ansi "$text")
    if ((${#plain} > MENU_BOX_WIDTH)); then
        text=$(truncate_visible "$plain" "$MENU_BOX_WIDTH")
        plain=$(strip_ansi "$text")
    fi
    len=${#plain}
    left=$(( (MENU_BOX_WIDTH - len) / 2 ))
    right=$((MENU_BOX_WIDTH - len - left))
    ((left < 0)) && left=0
    ((right < 0)) && right=0
    print_box_line "${color}$(printf '%*s%s%*s' "$left" "" "$plain" "$right")${RESET}"
}

render_menu_option() {
    local item="$1"
    local emphasis="${2:-normal}"
    local num="${item%% *}"
    local label="${item#* - }"
    # Compatível com itens antigos "N • label"
    if [[ "$item" == *" • "* ]]; then
        label="${item#* • }"
    fi
    local content

    if is_narrow_menu; then
        if [[ "$emphasis" == "red" ]]; then
            content="${RED}[${num}] ${label}${RESET}"
        else
            content="${WHITE}[${CYAN}${num}${WHITE}] ${BLUE}${label}${RESET}"
        fi
    else
    if [[ "$emphasis" == "red" ]]; then
        content="${RED}  [${num}] ${label}${RESET}"
    else
        content="${WHITE}  [${CYAN}${num}${WHITE}] ${BLUE}${label}${RESET}"
        fi
    fi
    print_box_line "$content"
}

print_header() {
    clear
    refresh_menu_layout
    print_box_open
    local title="${PROJECT_NAME}"
    local title_len=${#title}
    local title_left=$(( (MENU_BOX_WIDTH - title_len) / 2 ))
    local title_right=$((MENU_BOX_WIDTH - title_len - title_left))
    ((title_left < 0)) && title_left=0
    ((title_right < 0)) && title_right=0
    print_box_line "${BG_BLUE}${WHITE}$(printf '%*s%s%*s' "$title_left" "" "$title" "$title_right")${RESET}"
    if is_narrow_menu; then
        print_box_heading "BadVPN UDP Gateway"
    else
        print_box_heading "BadVPN UDP Gateway Manager"
    fi
    print_box_close
    echo
}

print_status() {
    local udpgw_ports udpgw_status ver

    udpgw_ports=$(format_udpgw_ports_status)
    if [[ "$udpgw_ports" == *":ON"* ]] || systemctl is-active --quiet "$UDPGW_SERVICE_NAME" 2>/dev/null; then
        udpgw_status="$(mark_online)"
    else
        udpgw_status="$(mark_offline)"
    fi
    ver=$(get_installed_udpgw_version_label)

    print_box_open
    if is_narrow_menu; then
        print_box_line "${WHITE}UDPgw: ${udpgw_status}${WHITE} ${CYAN}${udpgw_ports}${RESET}"
        print_box_line "${WHITE}Versao: ${CYAN}v${ver}${RESET}"
    else
        print_box_line "${WHITE} UDP Gateway: ${udpgw_status}${WHITE} portas ${CYAN}${udpgw_ports}${RESET}"
        print_box_line "${WHITE} Binario: ${CYAN}v${ver}${RESET} ${GRAY}(${UDPGW_BIN})${RESET}"
    fi
    print_box_close
    echo
}

print_success() {
    echo -e "${GREEN}$1${RESET}"
}

print_error() {
    echo -e "${RED}$1${RESET}"
}

print_info() {
    echo -e "${CYAN}$1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}$1${RESET}"
}

prompt_input() {
    echo -e "${BLUE}$1${RESET}"
    read -rp "> " response
    echo "$response"
}

pause() {
    echo
    print_warning "Pressione Enter para continuar..."
    read -r
}
is_port_in_use() {
    local port="$1"
    command -v ss >/dev/null 2>&1 && ss -tuln | grep -q ":$port "
}
validate_port() {
    local port="$1"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "Porta deve ser um número!"
        return 1
    fi
    
    if [[ "$port" -lt "$MIN_PORT" || "$port" -gt "$MAX_PORT" ]]; then
        print_error "Porta deve estar entre $MIN_PORT e $MAX_PORT!"
        return 1
    fi
    
    return 0
}

check_port_available() {
    local port="$1"
    local except_port="${2:-}"

    if [[ -n "$except_port" && "$port" == "$except_port" ]]; then
        return 0
    fi

    if is_port_in_use "$port"; then
        print_error "Porta $port já está em uso!"
        return 1
    fi

    return 0
}

is_port_free() {
    local port="$1"
    ! is_port_in_use "$port"
}

confirm_action() {
    local message="$1"
    local default_answer="${2:-n}"
    # Mensagens em stderr: permite uso futuro em $(...) sem engolir o prompt.
    echo -e "${YELLOW}$message (s/N)${RESET}" >&2
    read -rp "> " response
    response=${response:-$default_answer}
    case "${response,,}" in
        s|sim|y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_with_default() {
    local message="$1"
    local default="$2"
    local value
    # Prompt em stderr — o valor retorna em stdout para $(prompt_with_default ...).
    echo -e "${BLUE}${message} ${GRAY}[${default}]${RESET}" >&2
    read -rp "> " value
    value=${value:-$default}
    printf '%s' "$value"
}
is_udpgw_installed() {
    [[ -x "$UDPGW_BIN" ]]
}

detect_udpgw_release_arch() {
    case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    i386 | i686) echo "386" ;;
    *) echo "amd64" ;;
    esac
}

get_installed_udpgw_version_label() {
    local ver=""
    if [[ -x "$UDPGW_BIN" ]]; then
        ver=$("$UDPGW_BIN" -version 2>/dev/null | tr -d 'v\r\n' || true)
    fi
    if [[ -z "$ver" && -f "$UDPGW_VERSION_FILE" ]]; then
        ver=$(tr -d '\r\n' <"$UDPGW_VERSION_FILE")
    fi
    echo "${ver:-desconhecida}"
}

fetch_latest_udpgw_release_tag() {
    local json tag
    json=$(curl -fsSL \
        -H "Cache-Control: no-cache" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${UDPGW_REPO}/releases/latest" 2>/dev/null || true)
    tag=$(echo "$json" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')
    [[ -n "$tag" ]] && echo "$tag"
}

download_udpgw_binary() {
    local tag="${1:-}"
    local arch filename url tmp http_status sums_url expected actual

    if [[ -z "$tag" ]]; then
        tag=$(fetch_latest_udpgw_release_tag || true)
    fi
    if [[ -z "$tag" ]]; then
        print_error "Não foi possível resolver a versão do UDP Gateway."
        return 1
    fi

    [[ "$tag" == v* ]] || tag="v${tag}"

    arch=$(detect_udpgw_release_arch)
    filename="udpgw-linux-${arch}"
    url="https://github.com/${UDPGW_REPO}/releases/download/${tag}/${filename}"

    tmp=$(mktemp)
    print_info "Baixando ${filename} (${tag})..."
    print_info "URL: ${url}"
    http_status=$(curl -fsSL -w "%{http_code}" -o "$tmp" "$url" 2>/dev/null || true)
    if [[ "$http_status" != "200" || ! -s "$tmp" ]]; then
        rm -f "$tmp"
        print_error "Falha ao baixar ${filename} (HTTP ${http_status:-000})."
        print_info "Release: https://github.com/${UDPGW_REPO}/releases/tag/${tag}"
        return 1
    fi

    sums_url="https://github.com/${UDPGW_REPO}/releases/download/${tag}/SHA256SUMS"
    if http_status=$(curl -fsSL -w "%{http_code}" -o "${tmp}.sums" "$sums_url" 2>/dev/null || true) && [[ "$http_status" == "200" ]]; then
        expected=$(grep -E "[[:space:]]${filename}$" "${tmp}.sums" | awk '{print $1}' | head -n1)
        if [[ -n "$expected" ]]; then
            actual=$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')
            if [[ -z "$actual" ]]; then
                actual=$(shasum -a 256 "$tmp" 2>/dev/null | awk '{print $1}')
            fi
            if [[ -n "$actual" && "$actual" != "$expected" ]]; then
                rm -f "$tmp" "${tmp}.sums"
                print_error "Checksum SHA256 inválido para ${filename}."
        return 1
    fi
            print_success "Integridade SHA256 verificada."
        fi
    fi
    rm -f "${tmp}.sums"

    sudo install -m 755 "$tmp" "$UDPGW_BIN"
    rm -f "$tmp"
    echo "${tag#v}" | sudo tee "$UDPGW_VERSION_FILE" >/dev/null
    print_success "Binário udpgw instalado: ${UDPGW_BIN} (${tag})"
    return 0
}

parse_udpgw_metric() {
    local name="$1"
    local body="$2"
    local value

    value=$(printf '%s\n' "$body" | awk -v n="$name" '$1 == n { print $2; exit }')
    [[ -n "$value" ]] || value="-"
    printf '%s' "$value"
}

format_udpgw_metric_line() {
    local label="$1"
    local value="$2"
    local warn="${3:-false}"
    local value_color="$CYAN"

    if [[ "$warn" == "true" && "$value" != "0" && "$value" != "0.0" && "$value" != "-" ]]; then
        value_color="$YELLOW"
    fi

    print_box_line "${WHITE}  ${label}: ${value_color}${value}${RESET}"
}

udpgw_metrics_value_color() {
    local value="$1"
    local warn="${2:-false}"
    if [[ "$warn" == "true" && "$value" != "0" && "$value" != "0.0" && "$value" != "-" ]]; then
        printf '%s' "$YELLOW"
    else
        printf '%s' "$CYAN"
    fi
}

udpgw_metrics_cursor_hide() {
    [[ -t 1 ]] || return 0
    command -v tput >/dev/null 2>&1 && tput civis 2>/dev/null || printf '\033[?25l'
}

udpgw_metrics_cursor_show() {
    [[ -t 1 ]] || return 0
    command -v tput >/dev/null 2>&1 && tput cnorm 2>/dev/null || printf '\033[?25h'
}

udpgw_metrics_cursor_up() {
    local n="$1"
    [[ -t 1 && "$n" -gt 0 ]] || return 0
    command -v tput >/dev/null 2>&1 && tput cuu "$n" 2>/dev/null || printf '\033[%dA' "$n"
}

udpgw_metrics_dyn_line() {
    print_box_line "$1"
    UDPGW_METRICS_DYN_LINES=$((UDPGW_METRICS_DYN_LINES + 1))
}

udpgw_metrics_dyn_kv() {
    local label="$1"
    local value="$2"
    local warn="${3:-false}"
    local value_color
    value_color=$(udpgw_metrics_value_color "$value" "$warn")
    udpgw_metrics_dyn_line "$(printf "${WHITE}  %-22s${RESET} ${value_color}%s${RESET}" "${label}:" "$value")"
}

udpgw_metrics_render_live_block() {
    local port="$1"
    local svc_active="$2"
    local metrics_ok="$3"
    local body="$4"

    UDPGW_METRICS_DYN_LINES=0

    if [[ "$svc_active" == "true" && "$metrics_ok" == "true" ]]; then
        udpgw_metrics_dyn_line "${WHITE}  Servico:${RESET}             $(mark_online)  ${GRAY}systemd + metrics OK${RESET}"
    elif [[ "$svc_active" == "true" ]]; then
        udpgw_metrics_dyn_line "${WHITE}  Servico:${RESET}             $(mark_online)  ${YELLOW}metricas indisponiveis${RESET}"
    elif [[ "$metrics_ok" == "true" ]]; then
        udpgw_metrics_dyn_line "${WHITE}  Servico:${RESET}             $(mark_offline) ${YELLOW}metricas respondendo${RESET}"
    else
        udpgw_metrics_dyn_line "${WHITE}  Servico:${RESET}             $(mark_offline)"
    fi

    udpgw_metrics_dyn_line "${GRAY}  Atualizado:${RESET}           ${WHITE}$(date +%H:%M:%S)${RESET}"
    print_box_divider
    UDPGW_METRICS_DYN_LINES=$((UDPGW_METRICS_DYN_LINES + 1))

    if [[ "$metrics_ok" != "true" ]]; then
        udpgw_metrics_dyn_kv "Clientes ativos" "-"
        udpgw_metrics_dyn_kv "Total aceitos" "-"
        udpgw_metrics_dyn_kv "Rejeitados" "-"
        udpgw_metrics_dyn_kv "Respostas descartadas" "-"
        udpgw_metrics_dyn_kv "Tamanho do mapa" "-"
        udpgw_metrics_dyn_kv "Panics" "-"
        udpgw_metrics_dyn_kv "Erros TCP" "-"
        udpgw_metrics_dyn_kv "Erros UDP" "-"
    else
        local active total rejected dropped mapping panics read_err udp_err
        active=$(parse_udpgw_metric "udpgw_active_clients" "$body")
        total=$(parse_udpgw_metric "udpgw_clients_total" "$body")
        rejected=$(parse_udpgw_metric "udpgw_clients_rejected_total" "$body")
        dropped=$(parse_udpgw_metric "udpgw_dropped_replies_total" "$body")
        mapping=$(parse_udpgw_metric "udpgw_mapping_size" "$body")
        panics=$(parse_udpgw_metric "udpgw_panics_total" "$body")
        read_err=$(parse_udpgw_metric "udpgw_read_errors_total" "$body")
        udp_err=$(parse_udpgw_metric "udpgw_udp_write_errors_total" "$body")
        udpgw_metrics_dyn_kv "Clientes ativos" "$active" "false"
        udpgw_metrics_dyn_kv "Total aceitos" "$total" "false"
        udpgw_metrics_dyn_kv "Rejeitados" "$rejected" "true"
        udpgw_metrics_dyn_kv "Respostas descartadas" "$dropped" "true"
        udpgw_metrics_dyn_kv "Tamanho do mapa" "$mapping" "false"
        udpgw_metrics_dyn_kv "Panics" "$panics" "true"
        udpgw_metrics_dyn_kv "Erros TCP" "$read_err" "true"
        udpgw_metrics_dyn_kv "Erros UDP" "$udp_err" "true"
    fi

    print_box_close
    UDPGW_METRICS_DYN_LINES=$((UDPGW_METRICS_DYN_LINES + 1))

    printf '\033[2K\r'
    echo -e "${GRAY}  Live refresh 2s | Enter para voltar${RESET}"
    UDPGW_METRICS_DYN_LINES=$((UDPGW_METRICS_DYN_LINES + 1))
}

UDPGW_ADV_PORT=""
UDPGW_MIGRATION_CHECKED=""

ensure_udpgw_dirs() {
    if ! mkdir -p /etc/udpgw "$UDPGW_CONFIG_DIR" 2>/dev/null; then
        if command -v sudo >/dev/null 2>&1; then
            sudo mkdir -p /etc/udpgw "$UDPGW_CONFIG_DIR" || return 1
        else
            print_error "Não foi possível criar ${UDPGW_CONFIG_DIR}"
            return 1
        fi
    fi
    return 0
}

ensure_udpgw_dirs_quiet() {
    [[ -d /etc/udpgw && -d "$UDPGW_CONFIG_DIR" ]] && return 0
    ensure_udpgw_dirs
}

get_udpgw_config_file() {
    local port="$1"
    echo "${UDPGW_CONFIG_DIR}/udpgw-${port}.conf"
}

get_udpgw_service_name() {
    local port="$1"
    echo "${UDPGW_SERVICE_PREFIX}-${port}"
}

get_udpgw_conf_value() {
    local port="$1"
    local key="$2"
    local default="${3:-}"
    local file val

    file=$(get_udpgw_config_file "$port")
    if [[ -f "$file" ]]; then
        val=$(grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2-)
        if [[ -n "$val" ]]; then
            printf '%s' "$val"
            return 0
        fi
    fi
    printf '%s' "$default"
}

set_udpgw_conf_key() {
    local port="$1"
    local key="$2"
    local value="$3"
    local file temp_file

    ensure_udpgw_dirs
    file=$(get_udpgw_config_file "$port")
    temp_file=$(mktemp)
    if [[ -f "$file" ]]; then
        grep -v "^${key}=" "$file" >"$temp_file" || true
    fi
    echo "${key}=${value}" >>"$temp_file"
    sudo mv "$temp_file" "$file"
    sudo chmod 644 "$file" 2>/dev/null || true
}

udpgw_metrics_port_from_listen() {
    local listen="$1"
    if [[ "$listen" =~ :([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

suggest_udpgw_metrics_listen() {
    local except_port="${1:-}"
    local try_p="$UDPGW_METRICS_BASE"
    local reserved=() f port listen mport

    for f in "$UDPGW_CONFIG_DIR"/udpgw-*.conf; do
        [[ -f "$f" ]] || continue
        port=$(basename "$f" .conf | sed -n 's/^udpgw-\([0-9]\+\)$/\1/p')
        [[ -z "$port" || "$port" == "$except_port" ]] && continue
        listen=$(grep '^METRICS_LISTEN=' "$f" 2>/dev/null | head -n1 | cut -d= -f2-)
        mport=$(udpgw_metrics_port_from_listen "${listen:-127.0.0.1:9091}")
        [[ -n "$mport" ]] && reserved+=("$mport")
    done

    while true; do
        local taken="false"
        for mport in "${reserved[@]}"; do
            [[ "$mport" == "$try_p" ]] && taken="true" && break
        done
        if [[ "$taken" == true ]] || is_port_in_use "$try_p"; then
            try_p=$((try_p + 1))
            continue
        fi
        break
    done
    echo "127.0.0.1:${try_p}"
}

udpgw_fix_all_metrics_collisions() {
    local ports=() port listen mport try_p
    local -a used=()
    local -a changed=()

    while IFS= read -r port; do
        [[ -n "$port" ]] && ports+=("$port")
    done < <(list_configured_udpgw_ports | tr ',' '\n' | sort -n)

    for port in "${ports[@]}"; do
        listen=$(get_udpgw_conf_value "$port" "METRICS_LISTEN" "")
        [[ -z "$listen" ]] && listen="127.0.0.1:9091"
        mport=$(udpgw_metrics_port_from_listen "$listen")
        [[ -z "$mport" ]] && mport="$UDPGW_METRICS_BASE"

        local collision="false"
        for u in "${used[@]}"; do
            [[ "$u" == "$mport" ]] && collision="true" && break
        done

        if [[ "$collision" == true ]]; then
            try_p="$UDPGW_METRICS_BASE"
            while [[ " ${used[*]} " == *" $try_p "* ]]; do
                try_p=$((try_p + 1))
            done
            listen="127.0.0.1:${try_p}"
            set_udpgw_conf_key "$port" "METRICS_LISTEN" "$listen"
            mport=$try_p
            changed+=("$port")
        fi
        used+=("$mport")
    done

    for port in "${changed[@]}"; do
        local was="false"
        is_udpgw_port_active "$port" && was="true"
        apply_udpgw_service "$port" "$was" || true
    done
}

udpgw_metrics_conflict_with() {
    local port="$1"
    local listen mport other other_listen other_mport

    listen=$(get_udpgw_conf_value "$port" "METRICS_LISTEN" "")
    [[ -z "$listen" ]] && listen="127.0.0.1:9091"
    mport=$(udpgw_metrics_port_from_listen "$listen")

    for other in $(list_configured_udpgw_ports | tr ',' ' '); do
        [[ -z "$other" || "$other" == "$port" ]] && continue
        other_listen=$(get_udpgw_conf_value "$other" "METRICS_LISTEN" "")
        [[ -z "$other_listen" ]] && other_listen="127.0.0.1:9091"
        other_mport=$(udpgw_metrics_port_from_listen "$other_listen")
        if [[ -n "$mport" && "$mport" == "$other_mport" ]]; then
            echo "$other"
            return 0
        fi
    done
    return 1
}

write_udpgw_conf_new() {
    local port="$1"
    local metrics_listen listen config_file

    metrics_listen=$(suggest_udpgw_metrics_listen "$port")
    listen="0.0.0.0:${port}"
    config_file=$(get_udpgw_config_file "$port")

    if ! ensure_udpgw_dirs; then
        print_error "Falha ao preparar diretório de configuração udpgw."
        return 1
    fi

    if ! tee "$config_file" >/dev/null <<EOF
PORT=${port}
LISTEN=${listen}
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
    then
        print_error "Falha ao criar config: ${config_file}"
        return 1
    fi

    chmod 644 "$config_file" 2>/dev/null || true
    return 0
}

migrate_legacy_udpgw_if_needed() {
    local port=7400 listen file was_active="false" should_start="false"
    local legacy_service="/etc/systemd/system/${UDPGW_SERVICE_NAME}.service"
    local legacy_config="$UDPGW_CONFIG_FILE"
    local has_legacy_service=false has_legacy_config=false

    [[ -n "$UDPGW_MIGRATION_CHECKED" ]] && return 0
    UDPGW_MIGRATION_CHECKED=1

    if [[ -f /etc/udpgw/.legacy-migrated ]]; then
        return 0
    fi

    [[ -f "$legacy_service" ]] && has_legacy_service=true
    [[ -f "$legacy_config" ]] && has_legacy_config=true
    [[ "$has_legacy_service" != true && "$has_legacy_config" != true ]] && return 0

    ensure_udpgw_dirs

    if systemctl is-active --quiet "$UDPGW_SERVICE_NAME" 2>/dev/null; then
        was_active="true"
    elif systemctl is-enabled --quiet "$UDPGW_SERVICE_NAME" 2>/dev/null; then
        should_start="true"
    fi
    [[ "$was_active" == "true" ]] && should_start="true"
    if [[ "$has_legacy_service" == true && -f "/etc/systemd/system/$(get_udpgw_service_name "$port").service" ]]; then
        should_start="true"
    fi

    if [[ "$has_legacy_config" == true ]]; then
        listen=$(grep '^LISTEN=' "$legacy_config" 2>/dev/null | head -n1 | cut -d= -f2-)
        if [[ "$listen" =~ :([0-9]+)$ ]]; then
            port="${BASH_REMATCH[1]}"
        fi
        file=$(get_udpgw_config_file "$port")
        if [[ ! -f "$file" ]]; then
            sudo cp "$legacy_config" "$file"
            set_udpgw_conf_key "$port" "PORT" "$port"
        fi
    else
        file=$(ls "$UDPGW_CONFIG_DIR"/udpgw-*.conf 2>/dev/null | head -n1 || true)
        if [[ -n "$file" ]]; then
            port=$(basename "$file" .conf | sed -n 's/^udpgw-\([0-9]\+\)$/\1/p')
        fi
        [[ -z "$port" ]] && port="$UDPGW_DEFAULT_PORT"
    fi

    apply_udpgw_service "$port" "$should_start" || true

    if [[ "$has_legacy_service" == true ]]; then
        sudo systemctl disable "$UDPGW_SERVICE_NAME" 2>/dev/null || true
        sudo systemctl stop "$UDPGW_SERVICE_NAME" 2>/dev/null || true
        sudo rm -f "$legacy_service"
        sudo systemctl daemon-reload
    fi

    if [[ "$has_legacy_config" == true ]]; then
        sudo mv "$legacy_config" "${legacy_config}.migrated.bak" 2>/dev/null || sudo rm -f "$legacy_config"
    fi

    echo "1" | sudo tee /etc/udpgw/.legacy-migrated >/dev/null
    return 0
}

list_configured_udpgw_ports() {
    local ports=() f port service_file

    for service_file in /etc/systemd/system/${UDPGW_SERVICE_PREFIX}-*.service; do
        [[ -f "$service_file" ]] || continue
        port=$(basename "$service_file" .service | sed -n "s/^${UDPGW_SERVICE_PREFIX}-\\([0-9]\\+\\)$/\\1/p")
        [[ -n "$port" ]] && ports+=("$port")
    done

    for f in "$UDPGW_CONFIG_DIR"/udpgw-*.conf; do
        [[ -f "$f" ]] || continue
        port=$(basename "$f" .conf | sed -n 's/^udpgw-\([0-9]\+\)$/\1/p')
        [[ -n "$port" ]] && ports+=("$port")
    done

    if [[ ${#ports[@]} -eq 0 ]]; then
        return 0
    fi
    printf '%s\n' "${ports[@]}" | sort -nu | paste -sd, - 2>/dev/null || true
}

is_udpgw_port_active() {
    local port="$1"
    systemctl is-active --quiet "$(get_udpgw_service_name "$port")" 2>/dev/null
}

is_udpgw_active() {
    local ports port
    if systemctl is-active --quiet "$UDPGW_SERVICE_NAME" 2>/dev/null; then
        return 0
    fi
    ports=$(list_configured_udpgw_ports)
    [[ -z "$ports" ]] && return 1
    IFS=',' read -ra pa <<< "$ports"
    for port in "${pa[@]}"; do
        is_udpgw_port_active "$port" && return 0
    done
    return 1
}

format_udpgw_ports_status() {
    local configured port mark line="" active_ports=""
    configured=$(list_configured_udpgw_ports)

    if [[ -z "$configured" ]]; then
        echo "nenhuma"
        return 0
    fi

    IFS=',' read -ra pa <<< "$configured"
    for port in "${pa[@]}"; do
        [[ -z "$port" ]] && continue
        if is_udpgw_port_active "$port"; then
            mark="ON"
            [[ -n "$active_ports" ]] && active_ports+=","
            active_ports+="$port"
        else
            mark="OFF"
        fi
        if [[ -n "$line" ]]; then line+=","; fi
        line+="${port}:${mark}"
    done
    echo "$line"
}

append_udpgw_flag_if_set() {
    local -n _cmd=$1
    local flag="$2"
    local value="$3"
    [[ -n "$value" && "$value" != "0" ]] && _cmd+=" ${flag} ${value}"
}

build_udpgw_command_from_conf() {
    local port="$1"
    local listen cmd val

    listen=$(get_udpgw_conf_value "$port" "LISTEN" "0.0.0.0:${port}")
    cmd="${UDPGW_BIN} -listen ${listen}"

    if [[ "$(get_udpgw_conf_value "$port" "DEBUG" "false")" == "true" ]]; then
        cmd+=" -debug"
    fi

    val=$(get_udpgw_conf_value "$port" "METRICS_LISTEN" "")
    [[ -n "$val" ]] && cmd+=" -metrics-listen ${val}"

    append_udpgw_flag_if_set cmd "-max-frame" "$(get_udpgw_conf_value "$port" "MAX_FRAME" "")"
    append_udpgw_flag_if_set cmd "-write-chan" "$(get_udpgw_conf_value "$port" "WRITE_CHAN" "")"
    val=$(get_udpgw_conf_value "$port" "UDP_BIND" "")
    [[ -n "$val" ]] && cmd+=" -udp-bind ${val}"
    append_udpgw_flag_if_set cmd "-udp-rbuf" "$(get_udpgw_conf_value "$port" "UDP_RBUF" "")"
    append_udpgw_flag_if_set cmd "-udp-wbuf" "$(get_udpgw_conf_value "$port" "UDP_WBUF" "")"
    val=$(get_udpgw_conf_value "$port" "MAP_TTL" "")
    [[ -n "$val" ]] && cmd+=" -map-ttl ${val}"
    val=$(get_udpgw_conf_value "$port" "REAP_EVERY" "")
    [[ -n "$val" ]] && cmd+=" -reap-every ${val}"
    val=$(get_udpgw_conf_value "$port" "IDLE_TIMEOUT" "")
    [[ -n "$val" ]] && cmd+=" -idle-timeout ${val}"
    append_udpgw_flag_if_set cmd "-max-client-conns" "$(get_udpgw_conf_value "$port" "MAX_CLIENT_CONNS" "")"
    append_udpgw_flag_if_set cmd "-max-map-entries" "$(get_udpgw_conf_value "$port" "MAX_MAP_ENTRIES" "")"
    append_udpgw_flag_if_set cmd "-max-clients" "$(get_udpgw_conf_value "$port" "MAX_CLIENTS" "")"
    val=$(get_udpgw_conf_value "$port" "AUTO_RESTART_INTERVAL" "")
    [[ -n "$val" ]] && cmd+=" -auto-restart-interval ${val}"
    val=$(get_udpgw_conf_value "$port" "AUTO_RESTART_GRACE" "")
    [[ -n "$val" ]] && cmd+=" -auto-restart-grace ${val}"

    printf '%s' "$cmd"
}

apply_udpgw_service() {
    local port="$1"
    local restart="${2:-false}"
    local service_name exec_start listen

    if ! is_udpgw_installed; then
        print_error "Binário udpgw não encontrado."
        return 1
    fi

    service_name=$(get_udpgw_service_name "$port")
    listen=$(get_udpgw_conf_value "$port" "LISTEN" "0.0.0.0:${port}")
    exec_start=$(build_udpgw_command_from_conf "$port")

    sudo tee "/etc/systemd/system/${service_name}.service" >/dev/null <<EOF
[Unit]
Description=BadVPN UDP Gateway (VeltrixUPGW) port ${port}
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=${exec_start}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    if [[ "$restart" == "true" ]]; then
        sudo systemctl enable "$service_name" >/dev/null 2>&1 || true
        sudo systemctl restart "$service_name"
    fi
    return 0
}

is_udpgw_port_configured() {
    local port="$1"
    [[ -f "$(get_udpgw_config_file "$port")" || -f "/etc/systemd/system/$(get_udpgw_service_name "$port").service" ]]
}

select_udpgw_port_interactive() {
    local _result_var="${1:?select_udpgw_port_interactive: variavel de retorno obrigatoria}"
    local prompt="${2:-Digite a porta TCP do gateway}"
    local selected configured

    configured=$(list_configured_udpgw_ports)
    if [[ -z "$configured" ]]; then
        print_error "Nenhuma porta udpgw configurada."
        return 1
    fi

    print_header
    echo -e "${BLUE}Portas: ${GREEN}$(format_udpgw_ports_status)${RESET}"
    echo -e "${BLUE}${prompt}:${RESET}"
    read -rp "> " selected
    selected=$(echo "$selected" | tr -d '[:space:]')

    if [[ -z "$selected" && "$configured" != *","* ]]; then
        selected="$configured"
    fi

    if [[ -z "$selected" ]]; then
        print_error "Informe a porta."
        return 1
    fi

    if ! validate_port "$selected"; then
        return 1
    fi

    if [[ ",${configured}," != *",${selected},"* ]]; then
        print_error "Porta ${selected} nao configurada."
        return 1
    fi

    printf -v "$_result_var" '%s' "$selected"
    return 0
}

show_udpgw_execstart_line() {
    local port="$1"
    local service_name exec_line
    service_name=$(get_udpgw_service_name "$port")
    exec_line=$(systemctl cat "$service_name" 2>/dev/null | grep -E '^ExecStart=' | head -n1 | sed 's/^ExecStart=//')
    if [[ -n "$exec_line" ]]; then
        echo -e "${GRAY}${exec_line}${RESET}"
    else
        print_warning "Unit systemd ainda não existe para porta ${port}."
    fi
}

udpgw_conf_or_default() {
    local port="$1"
    local key="$2"
    local fallback="${3:-}"
    local val

    val=$(get_udpgw_conf_value "$port" "$key" "$fallback")
    if [[ -n "$val" ]]; then
        printf '%s' "$val"
    else
        printf '%s' "(padrao)"
    fi
}

udpgw_apply_advanced_config() {
    local port="$1"
    local was="false"

    is_udpgw_port_active "$port" && was="true"
    apply_udpgw_service "$port" "$was"
    print_success "Configuracao aplicada na porta ${port}."
    show_udpgw_execstart_line "$port"
    pause
}

udpgw_advanced_network_submenu() {
    local port="$1"
    local choice val

    while true; do
        echo
        refresh_menu_layout
        print_box_open
        print_box_heading "REDE - porta ${port}" "$CYAN"
        print_box_divider
        print_box_line "${WHITE}  Listen (-listen)${RESET}          ${CYAN}$(get_udpgw_conf_value "$port" LISTEN "0.0.0.0:${port}")${RESET}"
        print_box_line "${WHITE}  Metrics (-metrics-listen)${RESET} ${CYAN}$(udpgw_conf_or_default "$port" METRICS_LISTEN)${RESET}"
        print_box_line "${WHITE}  UDP bind (-udp-bind)${RESET}      ${CYAN}$(udpgw_conf_or_default "$port" UDP_BIND)${RESET}"
        print_box_divider
        render_menu_option "1 • Alterar Listen"
        render_menu_option "2 • Alterar Metrics"
        render_menu_option "3 • Alterar UDP bind"
        render_menu_option "0 • Voltar" "red"
    print_box_close
    echo
    
        read -rp "$(echo -e "${BLUE}Selecione [0-3]:${RESET} ")" choice
        case "$choice" in
        1)
            val=$(prompt_with_default "Listen (-listen)" "$(get_udpgw_conf_value "$port" LISTEN "0.0.0.0:${port}")")
            set_udpgw_conf_key "$port" "LISTEN" "$val"
            ;;
        2)
            val=$(prompt_with_default "Metrics (-metrics-listen, vazio=padrao)" "$(get_udpgw_conf_value "$port" METRICS_LISTEN "")")
            if [[ -z "$val" && "$(list_configured_udpgw_ports)" == *","* ]]; then
                val=$(suggest_udpgw_metrics_listen "$port")
                print_info "Multi-instancia: metrics unico sugerido ${val}"
            fi
            set_udpgw_conf_key "$port" "METRICS_LISTEN" "$val"
            ;;
        3)
            val=$(prompt_with_default "UDP bind IP (-udp-bind, vazio=padrao)" "$(get_udpgw_conf_value "$port" UDP_BIND "")")
            set_udpgw_conf_key "$port" "UDP_BIND" "$val"
            ;;
        0) return 0 ;;
        *) print_error "Opcao invalida: $choice" ;;
        esac
    done
}

udpgw_advanced_perf_submenu() {
    local port="$1"
    local choice val

    while true; do
        echo
        refresh_menu_layout
        print_box_open
        print_box_heading "PERFORMANCE - porta ${port}" "$CYAN"
        print_box_divider
        print_box_line "${WHITE}  Max frame (-max-frame)${RESET}    ${CYAN}$(udpgw_conf_or_default "$port" MAX_FRAME)${RESET}"
        print_box_line "${WHITE}  Write chan (-write-chan)${RESET}  ${CYAN}$(udpgw_conf_or_default "$port" WRITE_CHAN)${RESET}"
        print_box_line "${WHITE}  UDP rbuf (-udp-rbuf)${RESET}      ${CYAN}$(udpgw_conf_or_default "$port" UDP_RBUF)${RESET}"
        print_box_line "${WHITE}  UDP wbuf (-udp-wbuf)${RESET}      ${CYAN}$(udpgw_conf_or_default "$port" UDP_WBUF)${RESET}"
        print_box_divider
        render_menu_option "1 • Alterar max frame"
        render_menu_option "2 • Alterar write channel"
        render_menu_option "3 • Alterar UDP read buffer"
        render_menu_option "4 • Alterar UDP write buffer"
        render_menu_option "0 • Voltar" "red"
        print_box_close
        echo

        read -rp "$(echo -e "${BLUE}Selecione [0-4]:${RESET} ")" choice
        case "$choice" in
        1)
            val=$(prompt_with_default "Max frame bytes (-max-frame, vazio=padrao)" "$(get_udpgw_conf_value "$port" MAX_FRAME "")")
            set_udpgw_conf_key "$port" "MAX_FRAME" "$val"
            ;;
        2)
            val=$(prompt_with_default "Write channel (-write-chan, vazio=padrao)" "$(get_udpgw_conf_value "$port" WRITE_CHAN "")")
            set_udpgw_conf_key "$port" "WRITE_CHAN" "$val"
            ;;
        3)
            val=$(prompt_with_default "UDP read buffer (-udp-rbuf, vazio=padrao)" "$(get_udpgw_conf_value "$port" UDP_RBUF "")")
            set_udpgw_conf_key "$port" "UDP_RBUF" "$val"
            ;;
        4)
            val=$(prompt_with_default "UDP write buffer (-udp-wbuf, vazio=padrao)" "$(get_udpgw_conf_value "$port" UDP_WBUF "")")
            set_udpgw_conf_key "$port" "UDP_WBUF" "$val"
            ;;
        0) return 0 ;;
        *) print_error "Opcao invalida: $choice" ;;
        esac
    done
}

udpgw_advanced_limits_submenu() {
    local port="$1"
    local choice val

    while true; do
        echo
        refresh_menu_layout
        print_box_open
        print_box_heading "LIMITES - porta ${port}" "$CYAN"
        print_box_divider
        print_box_line "${WHITE}  Max client conns${RESET}  ${CYAN}$(udpgw_conf_or_default "$port" MAX_CLIENT_CONNS)${RESET}"
        print_box_line "${WHITE}  Max map entries${RESET}   ${CYAN}$(udpgw_conf_or_default "$port" MAX_MAP_ENTRIES)${RESET}"
        print_box_line "${WHITE}  Max clients${RESET}       ${CYAN}$(udpgw_conf_or_default "$port" MAX_CLIENTS)${RESET}"
        print_box_divider
        render_menu_option "1 • Alterar max client conns"
        render_menu_option "2 • Alterar max map entries"
        render_menu_option "3 • Alterar max clients"
        render_menu_option "0 • Voltar" "red"
        print_box_close
        echo

        read -rp "$(echo -e "${BLUE}Selecione [0-3]:${RESET} ")" choice
        case "$choice" in
        1)
            val=$(prompt_with_default "Max client conns (-max-client-conns, vazio=padrao)" "$(get_udpgw_conf_value "$port" MAX_CLIENT_CONNS "")")
            set_udpgw_conf_key "$port" "MAX_CLIENT_CONNS" "$val"
            ;;
        2)
            val=$(prompt_with_default "Max map entries (-max-map-entries, vazio=padrao)" "$(get_udpgw_conf_value "$port" MAX_MAP_ENTRIES "")")
            set_udpgw_conf_key "$port" "MAX_MAP_ENTRIES" "$val"
            ;;
        3)
            val=$(prompt_with_default "Max clients (-max-clients, vazio=padrao)" "$(get_udpgw_conf_value "$port" MAX_CLIENTS "")")
            set_udpgw_conf_key "$port" "MAX_CLIENTS" "$val"
            ;;
        0) return 0 ;;
        *) print_error "Opcao invalida: $choice" ;;
        esac
    done
}

udpgw_advanced_timeouts_submenu() {
    local port="$1"
    local choice val

    while true; do
        echo
        refresh_menu_layout
        print_box_open
        print_box_heading "TIMEOUTS - porta ${port}" "$CYAN"
        print_box_divider
        print_box_line "${WHITE}  Map TTL (-map-ttl)${RESET}                 ${CYAN}$(udpgw_conf_or_default "$port" MAP_TTL)${RESET}"
        print_box_line "${WHITE}  Reap every (-reap-every)${RESET}           ${CYAN}$(udpgw_conf_or_default "$port" REAP_EVERY)${RESET}"
        print_box_line "${WHITE}  Idle timeout (-idle-timeout)${RESET}       ${CYAN}$(udpgw_conf_or_default "$port" IDLE_TIMEOUT)${RESET}"
        print_box_line "${WHITE}  Auto-restart interval${RESET}                ${CYAN}$(udpgw_conf_or_default "$port" AUTO_RESTART_INTERVAL)${RESET}"
        print_box_line "${WHITE}  Auto-restart grace${RESET}                   ${CYAN}$(udpgw_conf_or_default "$port" AUTO_RESTART_GRACE)${RESET}"
        print_box_divider
        render_menu_option "1 • Alterar map TTL"
        render_menu_option "2 • Alterar reap every"
        render_menu_option "3 • Alterar idle timeout"
        render_menu_option "4 • Alterar auto-restart interval"
        render_menu_option "5 • Alterar auto-restart grace"
        render_menu_option "0 • Voltar" "red"
        print_box_close
        echo

        read -rp "$(echo -e "${BLUE}Selecione [0-5]:${RESET} ")" choice
        case "$choice" in
        1)
            val=$(prompt_with_default "Map TTL (-map-ttl, ex: 90s, vazio=padrao)" "$(get_udpgw_conf_value "$port" MAP_TTL "")")
            set_udpgw_conf_key "$port" "MAP_TTL" "$val"
            ;;
        2)
            val=$(prompt_with_default "Reap every (-reap-every, ex: 10s, vazio=padrao)" "$(get_udpgw_conf_value "$port" REAP_EVERY "")")
            set_udpgw_conf_key "$port" "REAP_EVERY" "$val"
            ;;
        3)
            val=$(prompt_with_default "Idle timeout (-idle-timeout, ex: 2m, vazio=padrao)" "$(get_udpgw_conf_value "$port" IDLE_TIMEOUT "")")
            set_udpgw_conf_key "$port" "IDLE_TIMEOUT" "$val"
            ;;
        4)
            val=$(prompt_with_default "Auto-restart interval (-auto-restart-interval, vazio=padrao)" "$(get_udpgw_conf_value "$port" AUTO_RESTART_INTERVAL "")")
            set_udpgw_conf_key "$port" "AUTO_RESTART_INTERVAL" "$val"
            ;;
        5)
            val=$(prompt_with_default "Auto-restart grace (-auto-restart-grace, vazio=padrao)" "$(get_udpgw_conf_value "$port" AUTO_RESTART_GRACE "")")
            set_udpgw_conf_key "$port" "AUTO_RESTART_GRACE" "$val"
            ;;
        0) return 0 ;;
        *) print_error "Opcao invalida: $choice" ;;
        esac
    done
}

prompt_udpgw_advanced_options() {
    local port="$1"
    local choice debug_val

    UDPGW_ADV_PORT="$port"
    while true; do
        echo
        refresh_menu_layout
        print_box_open
        print_box_heading "UDPGW AVANCADO - porta ${port}" "$CYAN"
        print_box_divider
        print_box_line "${GRAY}  Resumo (vazio no config = padrao do binario)${RESET}"
        print_box_line "${WHITE}  Listen:${RESET}  ${CYAN}$(get_udpgw_conf_value "$port" LISTEN "0.0.0.0:${port}")${RESET}"
        print_box_line "${WHITE}  Metrics:${RESET} ${CYAN}$(udpgw_conf_or_default "$port" METRICS_LISTEN)${RESET}"
        debug_val=$(get_udpgw_conf_value "$port" DEBUG "false")
        print_box_line "${WHITE}  Debug:${RESET}   ${CYAN}${debug_val}${RESET}"
        print_box_divider
        render_menu_option "1 • Rede (listen, metrics, udp-bind)"
        render_menu_option "2 • Performance (frame, buffers)"
        render_menu_option "3 • Limites de clientes"
        render_menu_option "4 • Timeouts e manutencao"
        render_menu_option "5 • Alternar debug (-debug)"
        render_menu_option "6 • Ver ExecStart"
        render_menu_option "7 • Salvar e aplicar systemd"
        render_menu_option "0 • Voltar" "red"
        print_box_close
        echo

        read -rp "$(echo -e "${BLUE}Selecione [0-7]:${RESET} ")" choice
        case "$choice" in
        1) udpgw_advanced_network_submenu "$port" ;;
        2) udpgw_advanced_perf_submenu "$port" ;;
        3) udpgw_advanced_limits_submenu "$port" ;;
        4) udpgw_advanced_timeouts_submenu "$port" ;;
        5)
            if [[ "$debug_val" == "true" ]]; then
                set_udpgw_conf_key "$port" "DEBUG" "false"
                print_success "Debug desativado."
            else
                set_udpgw_conf_key "$port" "DEBUG" "true"
                print_success "Debug ativado."
            fi
            ;;
        6)
            show_udpgw_execstart_line "$port"
            pause
            ;;
        7) udpgw_apply_advanced_config "$port" ;;
        0) return 0 ;;
        *) print_error "Opcao invalida: $choice" ;;
        esac
    done
}

udpgw_create_port() {
    print_header
    if ! is_udpgw_installed; then
        print_warning "Binario nao instalado. Baixando..."
        download_udpgw_binary || { pause; return 1; }
    fi

    local port
    port=$(prompt_with_default "Porta TCP do gateway (-listen)" "$UDPGW_DEFAULT_PORT")
    validate_port "$port" || { pause; return 1; }

    local existing
    existing=$(list_configured_udpgw_ports)
    if [[ ",${existing}," == *",${port},"* ]]; then
        print_warning "Porta ${port} ja configurada."
    else
        if ! check_port_available "$port"; then
            pause
            return 1
        fi
        if ! write_udpgw_conf_new "$port"; then
            pause
            return 1
        fi
        print_success "Config criada: $(get_udpgw_config_file "$port")"
    fi

    if confirm_action "Abrir opcoes avancadas antes de iniciar?" "n"; then
        prompt_udpgw_advanced_options "$port"
    fi

    if apply_udpgw_service "$port" "true"; then
        if is_udpgw_port_active "$port"; then
            print_success "UDP Gateway ativo na porta ${port}."
        else
            print_error "Servico pode nao ter iniciado."
            print_info "Logs: journalctl -u $(get_udpgw_service_name "$port") -n 30 --no-pager"
        fi
    fi
    pause
}

udpgw_start_port() {
    local port was="false"
    select_udpgw_port_interactive port "Porta para iniciar" || { pause; return 1; }
    is_udpgw_port_active "$port" && was="true"
    apply_udpgw_service "$port" "true"
    print_success "Porta ${port} iniciada."
    pause
}

udpgw_stop_port() {
    local port sn
    select_udpgw_port_interactive port "Porta para parar" || { pause; return 1; }
    sn=$(get_udpgw_service_name "$port")
    sudo systemctl stop "$sn" 2>/dev/null || true
    print_success "Porta ${port} parada."
    pause
}

udpgw_restart_port() {
    local port sn
    select_udpgw_port_interactive port "Porta para reiniciar" || { pause; return 1; }
    sn=$(get_udpgw_service_name "$port")
    sudo systemctl restart "$sn"
    print_success "Porta ${port} reiniciada."
    pause
}

udpgw_show_port_status() {
    local port listen metrics debug
    select_udpgw_port_interactive port "Porta para status" || { pause; return 1; }
    listen=$(get_udpgw_conf_value "$port" LISTEN "0.0.0.0:${port}")
    metrics=$(get_udpgw_conf_value "$port" METRICS_LISTEN "")
    debug=$(get_udpgw_conf_value "$port" DEBUG "false")

    print_header
    print_box_open
    print_box_heading "STATUS - porta ${port}" "$CYAN"
    print_box_divider
    if is_udpgw_port_active "$port"; then
        print_box_line "${WHITE}  Status: $(mark_online)${RESET}"
    else
        print_box_line "${WHITE}  Status: $(mark_offline)${RESET}"
    fi
    print_box_line "${WHITE}  Listen: ${BLUE}${listen}${RESET}"
    print_box_line "${WHITE}  Metrics: ${BLUE}${metrics:-padrao binario}${RESET}"
    print_box_line "${WHITE}  Debug: ${BLUE}${debug}${RESET}"
    print_box_line "${WHITE}  Config: ${BLUE}$(get_udpgw_config_file "$port")${RESET}"
    print_box_close
    echo
    show_udpgw_execstart_line "$port"
    pause
}

udpgw_view_port_logs() {
    local port sn
    select_udpgw_port_interactive port "Porta para logs" || { pause; return 1; }
    sn=$(get_udpgw_service_name "$port")
    print_info "Logs ${sn} (Ctrl+C para sair)..."
    sudo journalctl -u "$sn" -f
    pause
}

udpgw_remove_port() {
    local port sn
    select_udpgw_port_interactive port "Porta para remover" || { pause; return 1; }
    if ! confirm_action "Remover porta ${port} (servico + config)?" "n"; then
        pause
        return 0
    fi
    sn=$(get_udpgw_service_name "$port")
    sudo systemctl stop "$sn" 2>/dev/null || true
    sudo systemctl disable "$sn" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/${sn}.service"
    sudo rm -f "$(get_udpgw_config_file "$port")"
    sudo systemctl daemon-reload
    print_success "Porta ${port} removida."
    pause
}

get_udpgw_metrics_base_url_for_port() {
    local port="$1"
    local listen metrics_url
    listen=$(get_udpgw_conf_value "$port" "METRICS_LISTEN" "")
    listen=${listen:-127.0.0.1:9091}
    if [[ "$listen" == *"://"* ]]; then
        metrics_url="${listen%/}"
    else
        metrics_url="http://${listen}"
    fi
    printf '%s' "$metrics_url"
}

udpgw_show_metrics_for_port() {
    local port="$1"
    local metrics_url body svc_active metrics_ok listen_tcp metrics_cfg conflict_port
    local refresh_sec=2
    local static_drawn="false"
    local live_lines=0

    if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
        print_error "Porta invalida para metricas."
        pause
        return 1
    fi

    metrics_url=$(get_udpgw_metrics_base_url_for_port "$port")
    listen_tcp=$(get_udpgw_conf_value "$port" LISTEN "0.0.0.0:${port}")
    metrics_cfg=$(get_udpgw_conf_value "$port" "METRICS_LISTEN" "")
    if [[ -z "$metrics_cfg" ]]; then
        metrics_cfg="127.0.0.1:9091 (padrao binario)"
    fi
    conflict_port=$(udpgw_metrics_conflict_with "$port" 2>/dev/null || true)

    udpgw_metrics_cursor_hide
    clear
    refresh_menu_layout

    print_box_open
    print_box_heading "METRICAS UDPGW ${port}" "$CYAN"
    print_box_divider
    print_box_line "${WHITE}  TCP listen:${RESET}  ${CYAN}${listen_tcp}${RESET}"
    print_box_line "${WHITE}  Metrics cfg:${RESET} ${CYAN}${metrics_cfg}${RESET}"
    print_box_line "${WHITE}  Endpoint:${RESET}    ${BLUE}${metrics_url}/metrics${RESET}"
    if [[ -n "$conflict_port" ]]; then
        print_box_line "${YELLOW}  AVISO: metrics compartilhada com TCP ${conflict_port}${RESET}"
    fi
    print_box_divider
    static_drawn="true"

    while true; do
        svc_active="false"
        is_udpgw_port_active "$port" && svc_active="true"

        body=$(curl -fsSL --connect-timeout 2 --max-time 5 "${metrics_url}/metrics" 2>/dev/null || true)
        metrics_ok="false"
        [[ -n "$body" ]] && metrics_ok="true"

        if [[ "$static_drawn" == "true" ]]; then
            static_drawn="false"
        elif [[ -t 1 ]]; then
            udpgw_metrics_cursor_up "$live_lines"
        else
            udpgw_metrics_cursor_up 0
            clear
            refresh_menu_layout
            print_box_open
            print_box_heading "METRICAS UDPGW ${port}" "$CYAN"
            print_box_divider
            print_box_line "${WHITE}  TCP listen:${RESET}  ${CYAN}${listen_tcp}${RESET}"
            print_box_line "${WHITE}  Metrics cfg:${RESET} ${CYAN}${metrics_cfg}${RESET}"
            print_box_line "${WHITE}  Endpoint:${RESET}    ${BLUE}${metrics_url}/metrics${RESET}"
            if [[ -n "$conflict_port" ]]; then
                print_box_line "${YELLOW}  AVISO: metrics compartilhada com TCP ${conflict_port}${RESET}"
            fi
            print_box_divider
        fi

        udpgw_metrics_render_live_block "$port" "$svc_active" "$metrics_ok" "$body"
        live_lines=$UDPGW_METRICS_DYN_LINES

        if read -r -t "$refresh_sec" -n 1 _key 2>/dev/null; then
            break
        fi
    done

    udpgw_metrics_cursor_show
    echo
}

udpgw_show_metrics_menu() {
    local port
    select_udpgw_port_interactive port "Porta para metricas" || { pause; return 1; }
    udpgw_show_metrics_for_port "$port"
}

udpgw_edit_advanced_menu() {
    local port
    select_udpgw_port_interactive port "Porta para opcoes avancadas" || { pause; return 1; }
    prompt_udpgw_advanced_options "$port"
}


print_udpgw_menu() {
    local ports_status
    ports_status=$(format_udpgw_ports_status)
    print_box_open
    print_box_heading "UDP GATEWAY (udpgw)"
    print_box_divider
    print_box_line "${WHITE}  Portas: ${CYAN}${ports_status}${RESET}"
    print_box_divider
    local menu_items=(
        "1 • Abrir / criar porta"
        "2 • Iniciar porta"
        "3 • Parar porta"
        "4 • Reiniciar porta"
        "5 • Status & ExecStart"
        "6 • Painel de metricas"
        "7 • Visualizar logs"
        "8 • Opcoes avancadas (flags)"
        "9 • Instalar/atualizar binario"
        "M • Atualizar menu (ugw)"
        "A • Remover porta"
        "0 • Sair"
    )
    for item in "${menu_items[@]}"; do
        if [[ $item == *"Sair"* || $item == *"Remover"* ]]; then
            render_menu_option "$item" "red"
        else
            render_menu_option "$item"
        fi
    done
    print_box_close
    echo
}

udpgw_install_or_update() {
    print_header
    print_info "Instalando/atualizando binario udpgw..."
    if download_udpgw_binary; then
        local port
        for port in $(list_configured_udpgw_ports | tr ',' ' '); do
            [[ -z "$port" ]] && continue
            local was="false"
            is_udpgw_port_active "$port" && was="true"
            apply_udpgw_service "$port" "$was"
        done
    fi
    pause
}

ugw_update_menu_and_self() {
    print_header
    print_info "Atualizando menu e binario via instalador..."
    echo -e "${GRAY}curl -fsSL ${INSTALL_URL} | bash -s -- --update --yes${RESET}"
    echo
    if curl -fsSL "$INSTALL_URL" | bash -s -- --update --yes; then
        print_success "Atualizacao concluida."
        if [[ -x "$MENU_BIN" ]]; then
            print_warning "Recarregando menu..."
            pause
            exec "$MENU_BIN"
        fi
    else
        print_error "Falha na atualizacao."
    fi
    pause
}

udpgw_main_menu() {
    migrate_legacy_udpgw_if_needed || true
    udpgw_fix_all_metrics_collisions || true
    while true; do
        print_header
        print_status
        print_udpgw_menu
        local option
        read -rp "$(echo -e "${BLUE}Selecione [0-9/A/M]:${RESET} ")" option
        case "$option" in
        1) udpgw_create_port ;;
        2) udpgw_start_port ;;
        3) udpgw_stop_port ;;
        4) udpgw_restart_port ;;
        5) udpgw_show_port_status ;;
        6) udpgw_show_metrics_menu ;;
        7) udpgw_view_port_logs ;;
        8) udpgw_edit_advanced_menu ;;
        9) udpgw_install_or_update ;;
        m|M) ugw_update_menu_and_self ;;
        a|A) udpgw_remove_port ;;
        0) exit 0 ;;
        *) print_error "Opcao invalida: $option"; pause ;;
        esac
    done
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        print_error "Execute como root: sudo ugw"
        exit 1
    fi
}

main() {
    require_root
    migrate_legacy_udpgw_if_needed || true
    udpgw_main_menu
}

main "$@"
