#!/bin/bash
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket

# Ждём полной инициализации bluetooth
echo "[BT] Waiting for bluetooth controller..."
while ! bluetoothctl show &>/dev/null; do
    sleep 2
done

bluetoothctl power on
bluetoothctl agent NoInputNoOutput
bluetoothctl default-agent
bluetoothctl pairable on
bluetoothctl discoverable on

echo "[BT] Auto-pair service started"

# Автоподключение уже спаренных + периодический скан
while true; do
    # Сканируем 30 секунд для новых устройств
    timeout 30 bluetoothctl scan on >/dev/null 2>&1
    sleep 2

    # Подключаем все спаренные
    bluetoothctl devices Paired | while read -r _ MAC _; do
        [ -n "$MAC" ] && bluetoothctl connect "$MAC" 2>/dev/null
    done
    sleep 15
done
