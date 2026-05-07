#!/bin/bash

RED='\033[38;5;196m'
CRIMSON='\033[38;5;124m'
ASH='\033[38;5;237m'
NC='\033[0m'

step() { echo -ne "${ASH}[wait]${NC} $1..."; }
ok()   { echo -e "\r\033[2K${RED}[${RED}✓${NC}]${NC} $1"; }
fail() { echo -e "\r\033[2K${CRIMSON}[${CRIMSON}✗${NC}]${NC} $1"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 не установлен"; }

[ "$EUID" -ne 0 ] && fail "Требуются права root!"

optimize_network() {
    step "Оптимизация сетевого стека и включение BBR"
    need sysctl
    cat > /etc/sysctl.d/99-vps-optimize.conf << EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.core.somaxconn = 8192
net.ipv4.tcp_abort_on_overflow = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
EOF
    sysctl --system >/dev/null 2>&1
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        ok "Сетевой стек оптимизирован (BBR активен)"
    else
        ok "Сетевой стек настроен (BBR не поддерживается ядром)"
    fi
}

setup_ufw() {
    step "Настройка Firewall (UFW)"
    need ufw
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw default allow routed >/dev/null 2>&1
    for port in 443 8684 2244 5631; do
        ufw allow "$port" >/dev/null 2>&1
    done
    ufw --force enable >/dev/null 2>&1
    sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw 2>/dev/null || true
    ok "UFW активен, IPv6 отключен, порты открыты"
}

setup_ssh_port() {
    step "Настройка SSH порта"
    [ -f /etc/ssh/sshd_config ] || fail "sshd_config не найден"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    sed -i 's/^#Port 22/Port 2244/; s/^Port 22$/Port 2244/' /etc/ssh/sshd_config
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart sshd >/dev/null 2>&1 || true
    else
        service ssh restart >/dev/null 2>&1 || true
    fi
    ok "SSH порт: 2244"
}

setup_bash_customs() {
    step "Интеграция q.sh"
    sed -i '/alias q=/d' /root/.bashrc
    cat >> /root/.bashrc << 'EOF'

alias q='/root/q.sh'
alias status='q status'
alias start='q start all'
alias stop='q stop all'
alias restart='q restart all'
alias clear='q clear'
alias zip='q zip'
alias db='q db'
alias st='q st'
alias sr='sudo reboot'
EOF
    ok "Алиасы добавлены в .bashrc"
}

disable_ubuntu_motd() {
    step "Отключение стандартного MOTD Ubuntu"
    sed -i 's/PrintLastLog yes/PrintLastLog no/' /etc/ssh/sshd_config 2>/dev/null || true
    command -v systemctl >/dev/null 2>&1 && systemctl restart sshd >/dev/null 2>&1 || true
    ok "Стандартное MOTD отключено"
}

setup_motd() {
    step "Создание Bloody MOTD"
    chmod -x /etc/update-motd.d/* 2>/dev/null || true
    rm -f /etc/motd /etc/update-motd.d/* 2>/dev/null || true

    cat > /etc/update-motd.d/00-header << 'EOF'
#!/bin/bash

LOGO_COLOR='\033[38;5;160m'
DARK_RED='\033[38;5;88m'
GRAY='\033[38;5;242m'
NC='\033[0m'

TERM_WIDTH=$(stty size 2>/dev/null | awk '{print $2}')
[ -z "$TERM_WIDTH" ] && TERM_WIDTH=$(tput cols 2>/dev/null)
[ -z "$TERM_WIDTH" ] && TERM_WIDTH=80
LOGO_WIDTH=68
LEFT_INDENT=3
RIGHT_INDENT=3

LOGO_PAD_VAL=$(( (TERM_WIDTH - LOGO_WIDTH) / 2 ))
[ $LOGO_PAD_VAL -lt 0 ] && LOGO_PAD_VAL=0
LOGO_PAD=$(printf '%*s' "$LOGO_PAD_VAL" "")
LEFT_PAD=$(printf '%*s' "$LEFT_INDENT" "")

print_row() {
    local label="$1" value="$2"
    local spacer=$(( TERM_WIDTH - LEFT_INDENT - 20 - ${#value} - RIGHT_INDENT ))
    [ $spacer -lt 1 ] && spacer=1
    printf "${LEFT_PAD}${GRAY}%-20s${NC}%s${DARK_RED}%s${NC}\n" \
        "$label" "$(printf '%*s' "$spacer" "")" "$value"
}

echo -e "${LOGO_COLOR}"
printf "%s%s\n" "$LOGO_PAD" "                                         .x+=:.                  "
printf "%s%s\n" "$LOGO_PAD" "            ..             .ue~~%u.     z\`    ^%                 "
printf "%s%s\n" "$LOGO_PAD" "           @L            .d88   z88i       .   <k    x.    .     "
printf "%s%s\n" "$LOGO_PAD" "      .   9888i   .dL   x888E  *8888     .@8Ned8\"  .@88k  z88u   "
printf "%s%s\n" "$LOGO_PAD" " .udR88N  \`Y888k:*888. :8888E   ^\"\"    .@^%8888\"  ~\"8888 ^8888   "
printf "%s%s\n" "$LOGO_PAD" "<888'888k   888E  888I 98888E.=tWc.   x88:  \`)8b.   8888  888R   "
printf "%s%s\n" "$LOGO_PAD" "9888 'Y\"    888E  888I 98888N  '888N  8888N=*8888   8888  888R   "
printf "%s%s\n" "$LOGO_PAD" "9888        888E  888I 98888E   8888E  %8\"    R88   8888  888R   "
printf "%s%s\n" "$LOGO_PAD" "9888        888E  888I '8888E   8888E   @8Wou 9%    8888 ,888B . "
printf "%s%s\n" "$LOGO_PAD" "?8888u../  x888N><888'  ?888E   8888\" .888888P\`    \"8888Y 8888\"  "
printf "%s%s\n" "$LOGO_PAD" " \"8888P'    \"88\"  888    \"88&   888\"  \`   ^\"F       \`Y\"   'YP    "
printf "%s%s\n" "$LOGO_PAD" "   \"P'            88F      \"\"==*\"\"                               "
echo -e "${NC}"

UPTIME=$(uptime -p | sed 's/up //')
LOAD=$(awk '{print $1" "$2" "$3}' /proc/loadavg)
USERS=$(who | wc -l)
MEM=$(free -m | awk '/^Mem:/ {printf "%s/%s MiB (%.1f%%)", $3, $2, $3*100/$2}')
DISK=$(df -h / | awk '$NF=="/"{printf "%s/%s (%s)", $3,$2,$5}')
CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
IP=$(curl -s --max-time 2 ifconfig.me || echo "N/A")

print_row "Uptime" "$UPTIME"
print_row "Users" "$USERS online"
echo ""
print_row "CPU Load" "$LOAD"
print_row "CPU Usage" "${CPU:-N/A}"
print_row "Memory" "$MEM"
print_row "Disk /" "$DISK"
print_row "Public IP" "$IP"
echo
EOF

    chmod +x /etc/update-motd.d/00-header
    ok "Bloody MOTD установлен"
}

optimize_network
setup_ufw
setup_ssh_port
setup_bash_customs
disable_ubuntu_motd
setup_motd
