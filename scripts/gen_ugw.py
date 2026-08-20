#!/usr/bin/env python3
"""Gera ugw.sh a partir do vt.sh do VeltrixProxy."""
from pathlib import Path

VT_SH = Path(__file__).resolve().parents[2] / "VeltrixProxy" / "vt.sh"
OUT = Path(__file__).resolve().parents[1] / "ugw.sh"

vt = VT_SH.read_text(encoding="utf-8")
lines = vt.splitlines(keepends=True)


def slice_lines(start: int, end: int) -> str:
    return "".join(lines[start - 1 : end])


header = r'''#!/bin/bash

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

'''

ui = slice_lines(55, 219)

print_header = r'''
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

'''

helpers = slice_lines(329, 355) + slice_lines(499, 502) + slice_lines(658, 717)

# Core udpgw logic only (sem print_udpgw_menu / udpgw_main_menu originais)
udpgw = slice_lines(1798, 2965)

udpgw = udpgw.replace(
    "Description=${PROJECT_NAME} UDP Gateway port ${port}",
    "Description=BadVPN UDP Gateway (VeltrixUPGW) port ${port}",
)

tail = r'''
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
'''

out = header + ui + print_header + helpers + udpgw + tail
OUT.write_text(out, encoding="utf-8", newline="\n")
print(f"ugw.sh written: {len(out.splitlines())} lines -> {OUT}")
