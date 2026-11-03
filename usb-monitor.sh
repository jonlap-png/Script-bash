
#!/bin/bash

# Мониторинг подключенных USB-устройств
# Автор: System Administrator

LOGFILE="$HOME/usb-monitor.log"

# Функция записи событий
log_message() {
    local message="$1"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOGFILE"

    # Дополнительно отправляем событие в системный журнал
    logger -t usb-monitor "$message"
}

# Проверка необходимых утилит
for cmd in lsusb udevadm awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Ошибка: не найдена утилита $cmd"
        exit 1
    fi
done

# Вывод текущих USB-устройств
show_devices() {
    echo
    echo "========================================"
    echo " ТЕКУЩИЕ ПОДКЛЮЧЕННЫЕ USB-УСТРОЙСТВА"
    echo "========================================"

    lsusb

    echo "========================================"
    echo
}

# Вывод начального списка
show_devices

log_message "Мониторинг USB-устройств запущен"

# Переменные для обработки событий udev
action=""
devtype=""
vendor=""
model=""
product=""
devpath=""

# Обработка одного события
process_event() {
    # Нас интересуют только физические USB-устройства
    if [[ "$devtype" != "usb_device" ]]; then
        return
    fi

    local device_name="${vendor:-Неизвестный производитель}"
    local device_model="${model:-Неизвестная модель}"

    if [[ -n "$product" ]]; then
        device_name="$product"
        device_model=""
    fi

    case "$action" in
        add)
            log_message "НОВОЕ УСТРОЙСТВО ПОДКЛЮЧЕНО: $device_name $device_model | Путь: $devpath"
            ;;
        remove)
            log_message "УСТРОЙСТВО ОТКЛЮЧЕНО: $device_name $device_model | Путь: $devpath"
            ;;
    esac
}

# Сброс данных события
reset_event() {
    action=""
    devtype=""
    vendor=""
    model=""
    product=""
    devpath=""
}

# Запуск мониторинга событий udev
udevadm monitor --udev --property --subsystem-match=usb |
while IFS= read -r line; do

    # Пустая строка означает завершение блока события
    if [[ -z "$line" ]]; then
        process_event
        reset_event
        continue
    fi

    case "$line" in
        ACTION=*)
            action="${line#ACTION=}"
            ;;
        DEVTYPE=*)
            devtype="${line#DEVTYPE=}"
            ;;
        ID_VENDOR_FROM_DATABASE=*)
            vendor="${line#ID_VENDOR_FROM_DATABASE=}"
            ;;
        ID_MODEL_FROM_DATABASE=*)
            model="${line#ID_MODEL_FROM_DATABASE=}"
            ;;
        PRODUCT=*)
            product="${line#PRODUCT=}"
            ;;
        DEVPATH=*)
            devpath="${line#DEVPATH=}"
            ;;
    esac

done
