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
    echo -ne "${WAIT} Оптимизация сетевого стека и включение BBR..."

    # Проверка зависимостей
    for cmd in sysctl cat; do
        if ! command -v $cmd >/dev/null 2>&1; then
            update_status "$cmd не установлен" 1
            return 1
        fi
    done

    # Создание конфига с расширенными и сгруппированными параметрами
    cat > /etc/sysctl.d/99-vps-optimize.conf << EOF
# --- СКОРОСТЬ И АЛГОРИТМ ПЕРЕДАЧИ ---
# Использование FQ (Fair Queuing) обязательно для корректной работы BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0

# --- ПАМЯТЬ И БУФЕРЫ (Оптимизировано для 1Gbps+) ---
# Увеличиваем лимиты для высокоскоростных соединений
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 10000
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1

# --- ОБРАБОТКА UDP (Важно для VPN, Proxy и HTTP/3) ---
net.core.rmem_default = 262144
net.core.wmem_default = 262144

# --- ТАЙМАУТЫ И ПЕРЕИСПОЛЬЗОВАНИЕ ПОРТОВ ---
# Ускоряем освобождение ресурсов от "зависших" соединений
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.ip_local_port_range = 1024 65535

# --- ЗАЩИТА И СТАБИЛЬНОСТЬ ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.core.somaxconn = 8192
net.ipv4.tcp_abort_on_overflow = 0

# --- ОТКЛЮЧЕНИЕ IPV6 (Если не требуется) ---
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# --- ПРОЧЕЕ ---
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
EOF

    # Применяем настройки
    sysctl --system >/dev/null 2>&1
    
    # Проверка, включился ли BBR
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        update_status "Сетевой стек оптимизирован (BBR активен)"
    else
        update_status "Сетевой стек настроен (BBR не поддерживается ядром)"
    fi
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

    # Очистка старого
    sudo chmod -x /etc/update-motd.d/* 2>/dev/null || true
    sudo rm -f /etc/motd /etc/update-motd.d/* 2>/dev/null || true

    cat > /etc/update-motd.d/00-header << 'EOF'
#!/bin/bash

# --- КОНФИГУРАЦИЯ ЦВЕТОВ ---
LOGO_COLOR='\033[38;5;160m'  # Красный для лого
DARK_RED='\033[38;5;88m'    # ГЛУБОКИЙ ТЕМНО-КРАСНЫЙ для данных
GRAY='\033[38;5;242m'       # СЕРЫЙ для названий
NC='\033[0m'                # Сброс

# --- АВТО-ЦЕНТРИРОВАНИЕ ---
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
LOGO_WIDTH=65
PAD_WIDTH=$(( (TERM_WIDTH - LOGO_WIDTH) / 2 ))
[ $PAD_WIDTH -lt 0 ] && PAD_WIDTH=0
PAD=$(printf '%*s' "$PAD_WIDTH" "")

# --- ВЫВОД ЛОГОТИПА ---
echo -e "${LOGO_COLOR}"
printf "%s%s\n" "$PAD" "                                         .x+=:.                  "
printf "%s%s\n" "$PAD" "            ..             .ue~~%u.     z\`    ^%                 "
printf "%s%s\n" "$PAD" "           @L            .d88   z88i       .   <k    x.    .     "
printf "%s%s\n" "$PAD" "      .   9888i   .dL   x888E  *8888     .@8Ned8\"  .@88k  z88u   "
printf "%s%s\n" "$PAD" " .udR88N  \`Y888k:*888. :8888E   ^\"\"    .@^%8888\"  ~\"8888 ^8888   "
printf "%s%s\n" "$PAD" "<888'888k   888E  888I 98888E.=tWc.   x88:  \`)8b.   8888  888R   "
printf "%s%s\n" "$PAD" "9888 'Y\"    888E  888I 98888N  '888N  8888N=*8888   8888  888R   "
printf "%s%s\n" "$PAD" "9888        888E  888I 98888E   8888E  %8\"    R88   8888  888R   "
printf "%s%s\n" "$PAD" "9888        888E  888I '8888E   8888E   @8Wou 9%    8888 ,888B . "
printf "%s%s\n" "$PAD" "?8888u../  x888N><888'  ?888E   8888\" .888888P\`    \"8888Y 8888\"  "
printf "%s%s\n" "$PAD" " \"8888P'    \"88\"  888    \"88&   888\"  \`   ^\"F       \`Y\"   'YP    "
printf "%s%s\n" "$PAD" "   \"P'            88F      \"\"==*\"\"                               "
echo -e "${NC}"

# --- СБОР ИНФОРМАЦИИ ---
UPTIME=$(uptime -p | sed 's/up //')
LOAD=$(cat /proc/loadavg | awk '{print $1" "$2" "$3}')
USERS=$(who | wc -l)
MEM=$(free -m | awk '/^Mem:/ {printf "%s/%s MiB (%.1f%%)", $3, $2, $3*100/$2}')
DISK=$(df -h / | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')
CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}' || echo "N/A")
IP=$(curl -s --max-time 2 ifconfig.me || echo "N/A")

# --- ВЫВОД ДАННЫХ (Красное слева, Серое справа) ---
# INFO_PAD выравнивает весь блок под логотипом
INFO_PAD=$(printf '%*s' "$((PAD_WIDTH + 8))" "")

# %-25s - это ширина красной части. Заголовки (серые) будут стоять ровно справа от неё.
printf "${INFO_PAD}${DARK_RED}%-25s${NC} ${GRAY}%s${NC}\n" "$UPTIME" "Uptime"
printf "${INFO_PAD}${DARK_RED}%-25s${NC} ${GRAY}%s${NC}\n" "$USERS online" "Users"
echo ""
printf "${INFO_PAD}${DARK_RED}%-25s${NC} ${GRAY}%s${NC}\n" "$LOAD" "CPU Load"
printf "${INFO_PAD}${DARK_RED}%-25s${NC} ${GRAY}%s${NC}\n" "$CPU_USAGE" "CPU Usage"
printf "${INFO_PAD}${DARK_RED}%-25s${NC} ${GRAY}%s${NC}\n" "$MEM" "Memory"
printf "${INFO_PAD}${DARK_RED}%s/%s (%s)" "$(df -h / | awk 'NR==2 {print $3}')" "$(df -h / | awk 'NR==2 {print $2}')" "$(df -h / | awk 'NR==2 {print $5}')" > /tmp/disk_info
DISK_STR=$(cat /tmp/disk_info)
printf "${INFO_PAD}${DARK_RED}%-25s${NC} ${GRAY}%s${NC}\n" "$DISK_STR" "Disk /"
printf "${INFO_PAD}${DARK_RED}%-25s${NC} ${GRAY}%s${NC}\n" "$IP" "Public IP"

echo -e "${NC}"
EOF

    chmod +x /etc/update-motd.d/00-header
    update_status "Bloody MOTD обновлён (Инфо слева, Заголовки справа)"
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
