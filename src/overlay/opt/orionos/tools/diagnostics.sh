#!/bin/bash
LOG="/tmp/orionos-diag.log"
echo "=== OrionOS Diagnostics $(date) ===" | tee "$LOG"

echo -e "\n--- System ---" | tee -a "$LOG"
echo "Uptime: $(uptime)" | tee -a "$LOG"
echo "Load: $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$LOG"

echo -e "\n--- Thermal ---" | tee -a "$LOG"
for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/temp" 2>/dev/null)
    [ -n "$t" ] && echo "$(basename $z): $((t/1000))°C" | tee -a "$LOG"
done

echo -e "\n--- GPU Mali G31 ---" | tee -a "$LOG"
cat /sys/class/misc/mali0/device/clock 2>/dev/null | awk '{print "Clock: " $1/1000000 " MHz"}' | tee -a "$LOG"
cat /sys/class/misc/mali0/device/utilisation 2>/dev/null | awk '{print "Load: " $1 "%"}' | tee -a "$LOG"

echo -e "\n--- Bluetooth ---" | tee -a "$LOG"
systemctl is-active bluetooth | tee -a "$LOG"
bluetoothctl devices 2>/dev/null | tee -a "$LOG"

echo -e "\n--- Cores ---" | tee -a "$LOG"
echo "Installed: $(ls /usr/lib/aarch64-linux-gnu/libretro/*.so 2>/dev/null | wc -l)" | tee -a "$LOG"
ldd /usr/lib/aarch64-linux-gnu/libretro/*.so 2>/dev/null | grep 'not found' | tee -a "$LOG"

echo -e "\n--- Storage ---" | tee -a "$LOG"
df -h / /roms /roms2 2>/dev/null | tee -a "$LOG"

echo -e "\n--- Memory ---" | tee -a "$LOG"
free -h | tee -a "$LOG"

echo -e "\nDone. Log saved to $LOG"
