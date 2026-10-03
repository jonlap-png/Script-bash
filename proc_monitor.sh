#!/usr/bin/env bash
set -euo pipefail

# ===================================================================
# Конфигурация
# ===================================================================
PROC_DIR="/proc"
LOG_FILE="/var/log/proc_monitor.log"
STATE_FILE="/var/log/proc_monitor.state"   # хранит уже зафиксированные PID
MAX_PROC_NAME_LEN=30
MAX_CMDLINE_LEN=50

# Если нет прав на /var/log — работаем в текущей директории
if [[ ! -w "$(dirname "$LOG_FILE")" 2>/dev/null ]] && [[ "$EUID" -ne 0 ]]; then
    LOG_FILE="./proc_monitor.log"
    STATE_FILE="./proc_monitor.state"
fi

# ===================================================================
# 1.5 — Подготовка лога с отметкой времени запуска
# ===================================================================
TS_START=$(date '+%Y-%m-%d %H:%M:%S')
echo "============================================================" >> "$LOG_FILE"
echo "[$TS_START] Запуск мониторинга /proc" >> "$LOG_FILE"

# Загружаем список уже известных PID из файла состояния
declare -A SEEN_PIDS
if [[ -f "$STATE_FILE" ]]; then
    while IFS= read -r old_pid; do
        [[ -n "$old_pid" ]] && SEEN_PIDS["$old_pid"]=1
    done < "$STATE_FILE"
fi

# Очищаем файл состояния — запишем туда актуальные PID в конце
> "$STATE_FILE"

# ===================================================================
# 1.1 — Просмотр /proc и сбор номерных директорий
# 1.2 — Получение имени процесса через /proc/N/exe
# 1.3 — Сбор 4 параметров: status, cmdline, limits, fd
# 1.4 — Оформление в виде таблицы
# ===================================================================

# Заголовок таблицы
TABLE_HEADER=$(printf "%-7s | %-${MAX_PROC_NAME_LEN}s | %-6s | %-${MAX_CMDLINE_LEN}s | %-12s | %-5s" \
    "PID" "Name" "State" "Cmdline" "MaxFDs_Limit" "OpenFDs")
SEPARATOR=$(printf '%0.s-' {1..120})

NEW_COUNT=0
TOTAL_COUNT=0

echo "$SEPARATOR" >> "$LOG_FILE"
echo "$TABLE_HEADER" >> "$LOG_FILE"
echo "$SEPARATOR" >> "$LOG_FILE"

# --- Обход /proc ---
for proc_path in "$PROC_DIR"/*; do
    pid=$(basename "$proc_path")

    # 1.1 — Только числовые директории (PID)
    [[ ! "$pid" =~ ^[0-9]+$ ]] && continue

    TOTAL_COUNT=$((TOTAL_COUNT + 1))

    # 1.2 — Имя процесса через /proc/N/exe
    exe_link="${proc_path}/exe"
    proc_name="unknown"
    if [[ -L "$exe_link" ]]; then
        proc_name=$(readlink -f "$exe_link" 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    fi
    # Запасной вариант — через /proc/N/comm
    if [[ "$proc_name" == "unknown" ]] && [[ -f "${proc_path}/comm" ]]; then
        proc_name=$(head -n1 "${proc_path}/comm" 2>/dev/null | tr -d '\n')
    fi

    # 1.3 — Параметр 1: status (State)
    state="?"
    if [[ -f "${proc_path}/status" ]]; then
        state=$(grep "^State:" "${proc_path}/status" 2>/dev/null | awk '{print $2}')
    fi
    [[ -z "$state" ]] && state="?"

    # 1.3 — Параметр 2: cmdline
    cmdline=""
    if [[ -f "${proc_path}/cmdline" ]] && [[ -s "${proc_path}/cmdline" ]]; then
        # Нулевые байты заменяем на пробелы
        cmdline=$(tr '\0' ' ' < "${proc_path}/cmdline" 2>/dev/null | sed 's/ *$//')
    fi
    # Обрезаем длинные строки
    if [[ ${#cmdline} -gt $MAX_CMDLINE_LEN ]]; then
        cmdline="${cmdline:0:$((MAX_CMDLINE_LEN - 3))}..."
    fi
    [[ -z "$cmdline" ]] && cmdline="-"

    # 1.3 — Параметр 3: limits (Max open files)
    max_fds="-"
    if [[ -f "${proc_path}/limits" ]]; then
        max_fds=$(grep "^Max open files" "${proc_path}/limits" 2>/dev/null | awk '{print $4}')
    fi
    [[ -z "$max_fds" ]] && max_fds="-"

    # 1.3 — Параметр 4: fd (количество открытых дескрипторов)
    open_fds=0
    if [[ -d "${proc_path}/fd" ]]; then
        open_fds=$(ls -1 "${proc_path}/fd" 2>/dev/null | wc -l)
    fi

    # --- Обрезка имени процесса ---
    if [[ ${#proc_name} -gt $MAX_PROC_NAME_LEN ]]; then
        proc_name="${proc_name:0:$((MAX_PROC_NAME_LEN - 3))}..."
    fi

    # 1.4 — Форматирование строки таблицы
    row=$(printf "%-7s | %-${MAX_PROC_NAME_LEN}s | %-6s | %-${MAX_CMDLINE_LEN}s | %-12s | %-5s" \
        "$pid" "$proc_name" "$state" "$cmdline" "$max_fds" "$open_fds")

    # 1.5 — Только новые процессы попадают в лог
    if [[ -z "${SEEN_PIDS[$pid]+set}" ]]; then
        echo "$row" >> "$LOG_FILE"
        NEW_COUNT=$((NEW_COUNT + 1))
    fi

    # Сохраняем актуальный PID в файл состояния
    echo "$pid" >> "$STATE_FILE"
done

echo "$SEPARATOR" >> "$LOG_FILE"

# ===================================================================
# 1.5 — Итоговая запись в лог
# ===================================================================
TS_END=$(date '+%Y-%m-%d %H:%M:%S')
echo "Время завершения: $TS_END" >> "$LOG_FILE"
echo "Всего процессов: $TOTAL_COUNT | Новых: $NEW_COUNT" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Вывод в консоль
echo "Мониторинг завершён: всего $TOTAL_COUNT, новых $NEW_COUNT"
echo "Лог: $LOG_FILE"
