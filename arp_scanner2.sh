#!/bin/bash
#
# ARP-сканер подсети указанного интерфейса
# Использование: sudo ./arp_scanner2.sh <интерфейс>
#

set -euo pipefail

# ── Функции ──────────────────────────────────────────────────

# Проверка, что скрипт запущен от root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Ошибка: скрипт должен запускаться с правами root (используйте sudo)." >&2
        exit 1
    fi
}

# Проверка существования интерфейса
check_interface() {
    local iface="$1"
    if ! ip link show "$iface" &>/dev/null; then
        echo "Ошибка: интерфейс '$iface' не найден." >&2
        exit 1
    fi
}

# Получение IPv4-адреса и маски интерфейса в формате a.b.c.d/prefix
get_network() {
    local iface="$1"
    # Извлекаем строку вида "192.168.1.5/24" из вывода ip a
    local cidr
    cidr=$(ip -4 -o addr show dev "$iface" 2>/dev/null \
           | awk '{print $4}' | head -1)

    if [[ -z "$cidr" ]] || [[ "$cidr" == "/" ]]; then
        echo "Ошибка: на интерфейсе '$iface' не настроен IPv4-адрес." >&2
        exit 1
    fi
    echo "$cidr"
}

# Вычисление базового адреса подсети (network) из CIDR
# Использует ipcalc для получения адреса сети
calc_network_address() {
    local cidr="$1"
    ipcalc "$cidr" 2>/dev/null | awk -F= '/^Network/{print $2}' | head -1
}

# Скан одного хоста
scan_host() {
    local ip="$1"
    local iface="$2"
    echo "[*] IP: $ip"
    arping -c 3 -i "$iface" "$ip" 2>/dev/null || true
}

# Сканирование всей подсети
scan_subnet() {
    local network="$1"   # например 192.168.1.0
    local iface="$2"

    # Разбиваем адрес сети на октеты
    IFS=. read -r o1 o2 o3 o4 <<< "$network"

    # Перебираем хосты 1..254 (0 — сеть, 255 — broadcast)
    local host
    for host in $(seq 1 254); do
        scan_host "${o1}.${o2}.${o3}.${host}" "$iface"
    done
}

# Печать справки
print_usage() {
    echo "Использование: sudo $0 <интерфейс>"
    echo "Пример:  sudo $0 eth0"
}

# ── Основная логика ───────────────────────────────────────────

main() {
    check_root

    # Единственный аргумент — интерфейс
    if [[ $# -lt 1 ]]; then
        print_usage
        exit 1
    fi

    local interface="$1"
    check_interface "$interface"

    echo "=== ARP-сканер ==="
    echo "Интерфейс: $interface"

    # Получаем CIDR (адрес/маска) интерфейса
    local cidr
    cidr=$(get_network "$interface")
    echo "Адрес/маска: $cidr"

    # Вычисляем адрес сети
    local network
    network=$(calc_network_address "$cidr")

    if [[ -z "$network" ]]; then
        echo "Ошибка: не удалось определить адрес сети для '$cidr'." >&2
        exit 1
    fi

    echo "Подсеть: $network/24"
    echo "Сканирование хостов 1–254 ..."
    echo "========================"

    scan_subnet "$network" "$interface"

    echo "========================"
    echo "Готово."
}

main "$@"
