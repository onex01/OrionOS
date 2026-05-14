#!/bin/bash
# Backup es_input.cfg при изменении через ES
cp /home/orion/.emulationstation/es_input.cfg /opt/orionos/configs/es_input.cfg.bak 2>/dev/null || true
chown orion:orion /opt/orionos/configs/es_input.cfg.bak 2>/dev/null || true
