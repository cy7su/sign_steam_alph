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
    ufw allow 6734 >/dev/null 2>&1
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
alias sr='sudo reboot'
EOF
    update_status "Алиасы добавлены в .bashrc"
}

setup_motd() {
    echo -ne "${WAIT} Создание Bloody MOTD..."

    if ! command -v cat >/dev/null 2>&1; then
        update_status "cat не установлен" 1
    fi

    [ -f /etc/motd ] && rm -f /etc/motd
    [ -d /etc/update-motd.d ] && rm -f /etc/update-motd.d/*
    cat > /etc/update-motd.d/00-header << 'EOF'
#!/bin/bash
BLOOD='\033[38;5;196m'
CRIMSON='\033[38;5;124m'
RUST='\033[38;5;131m'
ASH='\033[38;5;237m'
NC='\033[0m'

echo -e "${BLOOD}"
cat << 'ASCII'
⠄⠄⠄⠄⠄⣸⣿⣮⣝⢱⣶⢵⡚⣽⣵⣿⣦⣝⣄⠄⠄⠄⠄⠄⠄⠄⠄⠄
⠄⣤⣤⣦⣝⣙⡩⠭⡍⣿⣷⣶⣼⣦⣭⣝⡻⣿⣶⡢⠄⠄⠄⠄⠄⠄⠄⠄
⣾⣿⣿⠫⣰⣿⣿⣿⣧⢽⣿⣿⣿⣿⣿⣿⣿⡜⣿⣿⣅⠄⠄⠄⠄⠄⠄⠄
⢿⣿⡿⢰⣿⣿⣿⣿⣿⣷⣮⣛⢿⡿⡿⠿⢻⢡⣜⣿⣿⡼⣤⠄⠄⠄⠄⠄
⠈⣿⣧⢻⠟⠛⠻⣿⣿⣿⣿⣿⡆⣷⣿⣿⣿⣧⠳⣿⣿⣿⣿⠂⠄⠄⠄⠄
⠄⠘⣿⣞⠄⠺⠄⢸⣿⣿⣿⣿⠇⣾⣿⣿⣿⣿⠄⠈⠻⣿⠟⠄⠄⠄⠄⠄
⠄⠄⠸⢿⣷⣔⠶⢿⣿⣿⠿⣋⣾⣿⣿⡻⣿⣿⣷⣤⣤⣄⣀⠄⠄⠄⠄⠄
⠄⠄⠄⠄⠉⢻⣿⣗⡦⡠⠚⢿⣿⣿⣿⣿⣜⢿⣿⣿⣿⣿⣿⣷⣤⣀⡀⠄
⠄⠄⠄⠄⠄⠈⢺⢿⣿⣿⣷⣮⡛⢿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣻⣿⣿⣿⣦
⠄⠄⠄⠄⠄⠄⠄⠁⢻⣿⣿⣿⣿⣧⣛⢿⣿⣿⣾⣿⣿⣿⡇⣿⣿⣿⣿⣿
⠄⠄⠄⠄⠄⠄⠄⠄⠄⠈⠙⠿⢿⣿⣿⣷⣦⣏⣛⣝⡽⣙⢨⣿⣿⣿⣿⣿
⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠹⠗⡞⠬⠛⠻⠻⣿⣿⣿⣶⡡⣿⣿⣿⣿⣿
⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣴⣿⣿⣿⣿⣿⣷⣮⢻⡛⡧⢓⢹⣿⣿⣿⣿
⠄⠄⠄⠄⠄⠄⠄⠄⠄⢀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣷⣭⢂⠰⠡⢿⣿⣿⣿
ASCII
echo -e "${NC}"

if command -v uptime >/dev/null 2>&1; then
    uptime=$(uptime -p | sed 's/up //')
else
    uptime="uptime not installed"
fi
load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1" "$2" "$3}' || echo "unavailable")
if command -v free >/dev/null 2>&1; then
    mem=$(free -h | awk '/^Mem:/ {print $3"/"$2}')
else
    mem="free not installed"
fi
if command -v df >/dev/null 2>&1; then
    disk=$(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')
else
    disk="df not installed"
fi
if command -v curl >/dev/null 2>&1; then
    ipv4=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || echo "unavailable")
else
    ipv4="curl not installed"
fi

echo -e "${CRIMSON}SYSTEM INFO:${NC}"
printf "  ${RUST}%-10s${NC} %s\n" "Uptime" "$uptime"
printf "  ${RUST}%-10s${NC} %s\n" "Load"   "$load"
printf "  ${RUST}%-10s${NC} %s\n" "Memory" "$mem"
printf "  ${RUST}%-10s${NC} %s\n" "Disk"   "$disk"
printf "  ${RUST}%-10s${NC} %s\n" "IPv4"   "$ipv4"
echo ""
EOF
    if command -v chmod >/dev/null 2>&1; then
        chmod +x /etc/update-motd.d/00-header
    fi
    update_status "Баннер входа обновлен"
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
