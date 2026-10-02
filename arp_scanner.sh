#!/bin/bash

# ============================================================
# ARP-сканер сети с гибким выбором диапазона сканирования
# ============================================================

# --- Проверка прав root ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Ошибка: скрипт должен запускаться с правами root (используйте sudo)."
        exit 1
    fi
}

# --- Валидация одного октета (0-255) ---
validate_octet() {
    local octet="$1"
    if [[ "$octet" =~ ^([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- Валидация PREFIX (два октета xxx.xxx) ---
validate_prefix() {
    local prefix="$1"
    if [[ "$prefix" =~ ^([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- Проверка существования сетевого интерфейса ---
validate_interface() {
    local iface="$1"
    if ip link show "$iface" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# --- Сканирование одного IP-адреса ---
scan_host() {
    local ip="$1"
    local iface="$2"
    echo "[*] IP : $ip"
    arping -c 3 -i "$iface" "$ip" 2>/dev/null
}

# --- Сканирование всех хостов одной подсети ---
scan_subnet() {
    local prefix="$1"
    local subnet="$2"
    local iface="$3"
    for host in {1..255}; do
        scan_host "${prefix}.${subnet}.${host}" "$iface"
    done
}

# --- Сканирование всех подсетей и всех хостов ---
scan_all() {
    local prefix="$1"
    local iface="$2"
    for subnet in {1..255}; do
        scan_subnet "$prefix" "$subnet" "$iface"
    done
}

# --- Вывод справки ---
print_usage() {
    echo "Использование: sudo $0 <PREFIX> <INTERFACE> [SUBNET] [HOST]"
    echo ""
    echo "Параметры:"
    echo "  PREFIX     — первые два октета IPv4 (например, 192.168)"
    echo "  INTERFACE  — сетевой интерфейс (например, eth0)"
    echo "  SUBNET     — третий октет (0-255), необязательный"
    echo "  HOST       — четвёртый октет (0-255), необязательный"
    echo ""
    echo "Режимы:"
    echo "  sudo $0 192.168 eth0              — сканировать всю сеть /16"
    echo "  sudo $0 192.168 eth0 1            — сканировать подсеть 192.168.1.0/24"
    echo "  sudo $0 192.168 eth0 1 10         — сканировать один IP 192.168.1.10"
}

# ============================================================
# Основная логика
# ============================================================

check_root

PREFIX="${1:-NOT_SET}"
INTERFACE="${2:-}"
SUBNET="${3:-}"
HOST="${4:-}"

# Проверка PREFIX
if [[ "$PREFIX" = "NOT_SET" ]]; then
    echo "Ошибка: PREFIX должен быть передан первым позиционным аргументом."
    print_usage
    exit 1
fi

if ! validate_prefix "$PREFIX"; then
    echo "Ошибка: PREFIX должен быть в формате xxx.xxx (например, 192.168), каждый октет 0-255."
    exit 1
fi

# Проверка INTERFACE
if [[ -z "$INTERFACE" ]]; then
    echo "Ошибка: INTERFACE должен быть передан вторым позиционным аргументом."
    print_usage
    exit 1
fi

if ! validate_interface "$INTERFACE"; then
    echo "Ошибка: сетевой интерфейс '$INTERFACE' не найден."
    exit 1
fi

# Выбор режима сканирования
if [[ -n "$HOST" ]]; then
    # Режим 3: сканирование одного IP-адреса
    if ! validate_octet "$SUBNET"; then
        echo "Ошибка: SUBNET должен быть числом от 0 до 255."
        exit 1
    fi
    if ! validate_octet "$HOST"; then
        echo "Ошибка: HOST должен быть числом от 0 до 255."
        exit 1
    fi
    echo "[+] Режим: сканирование одного IP-адреса ${PREFIX}.${SUBNET}.${HOST}"
    scan_host "${PREFIX}.${SUBNET}.${HOST}" "$INTERFACE"

elif [[ -n "$SUBNET" ]]; then
    # Режим 2: сканирование одной подсети
    if ! validate_octet "$SUBNET"; then
        echo "Ошибка: SUBNET должен быть числом от 0 до 255."
        exit 1
    fi
    echo "[+] Режим: сканирование подсети ${PREFIX}.${SUBNET}.0/24"
    scan_subnet "$PREFIX" "$SUBNET" "$INTERFACE"

else
    # Режим 1: сканирование всей сети
    echo "[+] Режим: сканирование всей сети ${PREFIX}.0.0/16"
    scan_all "$PREFIX" "$INTERFACE"
fi
