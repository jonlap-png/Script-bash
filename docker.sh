
#!/bin/bash

# ==========================================
# INPUT MONITOR
# Мониторинг устройств ввода Linux
# ==========================================

BASE_DIR="$HOME/input-monitor"
INPUT_FILE="/proc/bus/input/devices"
STATE_FILE="$BASE_DIR/devices.state"
LOG_FILE="$BASE_DIR/input-monitor.log"

mkdir -p "$BASE_DIR"

# Проверка доступности файла
if [[ ! -r "$INPUT_FILE" ]]; then
    echo "Ошибка: невозможно прочитать $INPUT_FILE"
    exit 1
fi

# Массив текущих устройств
declare -A devices

# Переменные устройства
name=""
phys=""
sysfs=""
handlers=""

# Обработка одного устройства
process_device() {

    [[ -z "$name" && -z "$sysfs" ]] && return

    local id="${sysfs:-$name|$phys|$handlers}"

    devices["$id"]="$name"

}

# Чтение и разбор файла устройств
while IFS= read -r line || [[ -n "$line" ]]; do

    if [[ "$line" == I:* ]]; then
        process_device

        name=""
        phys=""
        sysfs=""
        handlers=""
    fi

    case "$line" in
        N:*)
            name="${line#N: Name=}"
            name="${name#\"}"
            name="${name%\"}"
            ;;
        P:*)
            phys="${line#P: Phys=}"
            ;;
        S:*)
            sysfs="${line#S: Sysfs=}"
            ;;
        H:*)
            handlers="${line#H: Handlers=}"
            ;;
    esac

done < "$INPUT_FILE"

# Обработка последнего устройства
process_device

# Функция записи в лог
write_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Вывод списка устройств при запуске
echo "======================================"
echo " ПОДКЛЮЧЕННЫЕ УСТРОЙСТВА ВВОДА"
echo "======================================"

for id in "${!devices[@]}"; do
    echo "Устройство: ${devices[$id]}"
    echo "Идентификатор: $id"
    echo "--------------------------------------"
done

# Запись времени выполнения
write_log "Проверка устройств выполнена. Найдено: ${#devices[@]}"

# Проверка первого запуска
if [[ ! -f "$STATE_FILE" ]]; then

    # Первый запуск: сохраняем существующие устройства
    for id in "${!devices[@]}"; do
        printf '%s\n' "$id"
    done > "$STATE_FILE"

    write_log "Первоначальный список устройств создан"

else

    # Загружаем предыдущий список
    declare -A old_devices

    while IFS= read -r id; do
        [[ -n "$id" ]] && old_devices["$id"]=1
    done < "$STATE_FILE"

    # Ищем новые устройства
    for id in "${!devices[@]}"; do

        if [[ -z "${old_devices[$id]+exists}" ]]; then

            echo "НОВОЕ УСТРОЙСТВО: ${devices[$id]}"

            write_log "НОВОЕ УСТРОЙСТВО: ${devices[$id]} | ID: $id"

        fi

    done

    # Обновляем список устройств
    for id in "${!devices[@]}"; do
        printf '%s\n' "$id"
    done > "$STATE_FILE"

fi

echo "======================================"
echo " Проверка завершена"
echo "======================================"
