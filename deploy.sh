#!/bin/bash

BLOOD='\033[38;5;196m'
CRIMSON='\033[38;5;124m'
DARK='\033[38;5;52m'
RUST='\033[38;5;131m'
ASH='\033[38;5;237m'
NC='\033[0m'

SUCCESS="${BLOOD}✓${NC}"
ERROR="${CRIMSON}✗${NC}"
WAIT="${ASH}[wait]${NC}"

update_status() {
    local text=$1
    local status=${2:-0}
    if [ "$status" -eq 0 ]; then
        echo -e "\r\033[2K${BLOOD}[${SUCCESS}]${NC} ${text}"
    else
        echo -e "\r\033[2K${CRIMSON}[${ERROR}]${NC} ${text}"
        exit 1
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${CRIMSON}[${ERROR}]${NC} Требуются права root!"
        exit 1
    fi
}


optimize_network() {
    echo -ne "${WAIT} Оптимизация сетевого стека..."

    if ! command -v sysctl >/dev/null 2>&1; then
        update_status "sysctl не установлен" 1
    fi

    if ! command -v cat >/dev/null 2>&1; then
        update_status "cat не установлен" 1
    fi

    cat > /etc/sysctl.d/99-vps-optimize.conf << EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 720000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 4096
net.ipv4.tcp_abort_on_overflow = 0
EOF
    sysctl -p /etc/sysctl.d/99-vps-optimize.conf >/dev/null 2>&1
    update_status "BBR включен, IPv6 отключен"
}

setup_ufw() {
    echo -ne "${WAIT} Настройка Firewall (UFW)..."

    if ! command -v ufw >/dev/null 2>&1; then
        update_status "UFW не установлен" 1
    fi

    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    ufw default allow routed >/dev/null 2>&1
    ufw allow 443 >/dev/null 2>&1
    ufw allow 8684 >/dev/null 2>&1
    ufw allow 2244 >/dev/null 2>&1
    ufw allow 5631 >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1

    sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw 2>/dev/null || true

    update_status "UFW активен, IPv6 отключен, порты открыты"
}

setup_ssh_port() {
    echo -ne "${WAIT} Настройка SSH порта..."

    if ! command -v sed >/dev/null 2>&1; then
        update_status "sed не установлен" 1
    fi

    if [ ! -f /etc/ssh/sshd_config ]; then
        update_status "sshd_config не найден" 1
    fi

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true

    sed -i 's/^#Port 22/Port 2244/' /etc/ssh/sshd_config
    sed -i 's/^Port 22$/Port 2244/' /etc/ssh/sshd_config

    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart sshd >/dev/null 2>&1 || true
    elif command -v service >/dev/null 2>&1; then
        service ssh restart >/dev/null 2>&1 || true
    fi

    update_status "SSH порт: 2244, hardening применен"
}

setup_bash_customs() {
    echo -ne "${WAIT} Интеграция q.sh..."

    if ! command -v sed >/dev/null 2>&1; then
        update_status "sed не установлен" 1
    fi

    sed -i '/alias q=/d' /root/.bashrc
    cat >> /root/.bashrc << 'EOF'

# --- RED PROTOCOL ALIASES ---
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
    update_status "Алиасы добавлены в .bashrc"
}

setup_motd() {
    echo -ne "${WAIT} Создание Bloody MOTD..."

    # Очистка старого MOTD
    sudo chmod -x /etc/update-motd.d/* 2>/dev/null || true
    sudo rm -f /etc/motd
    sudo rm -f /etc/update-motd.d/* 2>/dev/null || true

    cat > /etc/update-motd.d/00-header << 'EOF'
#!/bin/bash

# Цвета
BLOOD='\033[38;5;160m'     # Насыщенный красный для лого
DARK_RED='\033[38;5;88m'   # Темно-красный для инфо
GRAY='\033[38;5;244m'      # Серый для заголовков
NC='\033[0m'               # Сброс

# Функция для центрирования (добавляет пробелы перед лого)
# Логотип примерно 65 символов в ширину. Добавим отступ в 10 пробелов.
LOGO_PADDING="          "

echo -e "${BLOOD}"
echo "${LOGO_PADDING}                                         .x+=:.                  "
echo "${LOGO_PADDING}            ..             .ue~~%u.     z`    ^%                 "
echo "${LOGO_PADDING}           @L            .d88   z88i       .   <k    x.    .     "
echo "${LOGO_PADDING}      .   9888i   .dL   x888E  *8888     .@8Ned8\"  .@88k  z88u   "
echo "${LOGO_PADDING} .udR88N  `Y888k:*888. :8888E   ^\"\"    .@^%8888\"  ~\"8888 ^8888   "
echo "${LOGO_PADDING}<888'888k   888E  888I 98888E.=tWc.   x88:  `)8b.   8888  888R   "
echo "${LOGO_PADDING}9888 'Y\"    888E  888I 98888N  '888N  8888N=*8888   8888  888R   "
echo "${LOGO_PADDING}9888        888E  888I 98888E   8888E  %8\"    R88   8888  888R   "
echo "${LOGO_PADDING}9888        888E  888I '8888E   8888E   @8Wou 9%    8888 ,888B . "
echo "${LOGO_PADDING}?8888u../  x888N><888'  ?888E   8888\" .888888P`    \"8888Y 8888\"  "
echo "${LOGO_PADDING} \"8888P'    \"88\"  888    \"88&   888\"  `   ^\"F       `Y\"   'YP    "
echo "${LOGO_PADDING}   \"P'            88F      \"\"==*\"\"                               "
echo "${LOGO_PADDING}                 98\"                                             "
echo "${LOGO_PADDING}               ./\"                                               "
echo "${LOGO_PADDING}              ~`                                                 "
echo -e "${NC}"

# === Сбор информации ===
UPTIME=$(uptime -p | sed 's/up //')
LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}')
USERS=$(who | wc -l)

if command -v free >/dev/null 2>&1; then
    MEM=$(free -m | awk '/^Mem:/ {printf "%s/%s MiB (%.1f%%)", $3, $2, $3*100/$2}')
else
    MEM="N/A"
fi

if command -v df >/dev/null 2>&1; then
    DISK=$(df -h / | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')
else
    DISK="N/A"
fi

if command -v curl >/dev/null 2>&1; then
    IP=$(curl -s --max-time 4 ifconfig.me 2>/dev/null || echo "N/A")
else
    IP="N/A"
fi

CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}' || echo "N/A")

# === ВЫВОД (Названия слева серые, Инфо справа темно-красное) ===
# %-20s — резервирует 20 символов под название (выравнивание по левому краю)
# %s — выводит значение сразу после этого блока
INDENT="          " # Отступ для блока текста, чтобы был под логотипом

printf "${INDENT}${GRAY}%-20s${NC} ${DARK_RED}%s${NC}\n" "Uptime" "${UPTIME}"
printf "${INDENT}${GRAY}%-20s${NC} ${DARK_RED}%s online${NC}\n" "Users" "${USERS}"
echo ""
printf "${INDENT}${GRAY}%-20s${NC} ${DARK_RED}%s${NC}\n" "CPU Load" "${LOAD}"
printf "${INDENT}${GRAY}%-20s${NC} ${DARK_RED}%s${NC}\n" "CPU Usage" "${CPU_USAGE}"
printf "${INDENT}${GRAY}%-20s${NC} ${DARK_RED}%s${NC}\n" "Memory" "${MEM}"
printf "${INDENT}${GRAY}%-20s${NC} ${DARK_RED}%s${NC}\n" "Disk /" "${DISK}"
printf "${INDENT}${GRAY}%-20s${NC} ${DARK_RED}%s${NC}\n" "Public IP" "${IP}"
echo ""
EOF

    chmod +x /etc/update-motd.d/00-header
    update_status "Баннер входа обновлён (Центрированный Bloody MOTD)"
}

disable_ubuntu_motd() {
    echo -ne "${WAIT} Отключение стандартного сообщения Ubuntu..."
    sed -i 's/PrintLastLog yes/PrintLastLog no/' /etc/ssh/sshd_config 2>/dev/null || true
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart sshd >/dev/null 2>&1 || true
    fi
    update_status "Стандартное сообщение Ubuntu отключено"
}

check_root

optimize_network
setup_ufw
setup_ssh_port
setup_bash_customs
disable_ubuntu_motd
setup_motd
