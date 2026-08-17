#!/bin/bash

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo -e "=============================================="
echo -e "       LAMP SERVER DIAGNOSTIC REPORT"
echo -e "=============================================="
echo

# Ensure script is run with sudo/root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run with sudo: sudo $0${NC}"
    exit 1
fi

LOGFILE="/var/log/lamp_diag_$(date +%F_%H%M%S).log"
touch "$LOGFILE"
echo "LAMP Diagnostic started at $(date)" > "$LOGFILE"

# Arrays to store check results
declare -a CHECK_NAMES
declare -a CHECK_STATUSES
declare -a CHECK_MESSAGES
declare -a CHECK_DETAIL_CMDS

# Helper to add a check
add_check() {
    CHECK_NAMES+=("$1")
    CHECK_STATUSES+=("$2")
    CHECK_MESSAGES+=("$3")
    CHECK_DETAIL_CMDS+=("$4")
}

# --- Phase 1: Perform all checks (silent collection) ---

# 1. Apache Service
if systemctl is-active --quiet apache2; then
    add_check "Apache Service" "OK" "running" ""
else
    add_check "Apache Service" "ERROR" "not running" "systemctl status apache2 --no-pager -l"
fi

# 2. Apache Port 80
if ss -tln | grep -qE ':80[[:space:]]'; then
    add_check "Apache Port 80" "OK" "listening" ""
else
    add_check "Apache Port 80" "ERROR" "not listening" "ss -tlnp"
fi

# 3. MariaDB / MySQL
if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
    add_check "MariaDB Service" "OK" "running" ""
else
    add_check "MariaDB Service" "ERROR" "not running" "systemctl status mariadb --no-pager -l || systemctl status mysql --no-pager -l"
fi

# 4. PHP
if command -v php >/dev/null 2>&1; then
    PHP_VERSION=$(php -v | head -n1 | awk '{print $2}')
    add_check "PHP Installed" "OK" "version ${PHP_VERSION}" ""
else
    add_check "PHP Installed" "ERROR" "not installed" "dpkg -l | grep -i php || echo 'No PHP packages found'"
fi

# 5. Firewall (UFW)
if command -v ufw >/dev/null 2>&1; then
    add_check "UFW Installed" "OK" "installed" ""
    if ufw status | grep -q "Status: active"; then
        add_check "UFW Status" "OK" "active" ""
        UFW_OUTPUT=$(ufw status)
        for port in 22 80 443; do
            if echo "$UFW_OUTPUT" | grep -qE "^${port}(/tcp|/udp)?[[:space:]]+ALLOW"; then
                add_check "  UFW Port ${port}" "OK" "ALLOWED" ""
            else
                add_check "  UFW Port ${port}" "ERROR" "NOT ALLOWED" "ufw status verbose | grep -E '^${port}(/tcp|/udp)?' || echo 'Port ${port} rule missing'"
            fi
        done
    else
        add_check "UFW Status" "ERROR" "inactive" "ufw status verbose"
    fi
else
    add_check "UFW Installed" "ERROR" "not installed" "dpkg -l | grep ufw || echo 'UFW package not installed'"
fi

# 6. Virtual Host apach-sajt-1
if apache2ctl -S 2>/dev/null | grep -q "apach-sajt-1"; then
    add_check "VHost apach-sajt-1" "OK" "enabled" ""
else
    add_check "VHost apach-sajt-1" "ERROR" "not enabled" "apache2ctl -S 2>&1"
fi

# 7. Disk Usage
DISK_USAGE=$(df -h / | awk 'NR==2 {gsub("%","",$5); print $5}')
if [ "$DISK_USAGE" -lt 75 ]; then
    add_check "Disk Usage (/)" "OK" "${DISK_USAGE}% used" ""
elif [ "$DISK_USAGE" -ge 75 ] && [ "$DISK_USAGE" -le 90 ]; then
    add_check "Disk Usage (/)" "WARNING" "${DISK_USAGE}% used" "df -h /"
else
    add_check "Disk Usage (/)" "CRITICAL" "${DISK_USAGE}% used" "df -h /"
fi

# --- Phase 2: Write detailed error logs FIRST (for non-OK checks) ---
echo -e "=============================================="
echo -e "       DETAILED DIAGNOSTIC LOGS (Errors/Warnings)"
echo -e "=============================================="
echo
HAS_NON_OK=0
for i in "${!CHECK_NAMES[@]}"; do
    status="${CHECK_STATUSES[$i]}"
    detail_cmd="${CHECK_DETAIL_CMDS[$i]}"
    if [[ "$status" != "OK" ]] && [[ -n "$detail_cmd" ]]; then
        HAS_NON_OK=1
        name="${CHECK_NAMES[$i]}"
        echo -e "${YELLOW}--- Details for: $name ---${NC}"
        echo "--- Details for: $name ---" >> "$LOGFILE"
        bash -c "$detail_cmd" 2>&1 | tee -a "$LOGFILE" | sed 's/^/    /'
        echo -e "${YELLOW}------------------------------${NC}"
        echo "------------------------------" >> "$LOGFILE"
        echo
    fi
done

if [ $HAS_NON_OK -eq 0 ]; then
    echo -e "${GREEN}All checks passed! No detailed errors to display.${NC}"
    echo "All checks passed" >> "$LOGFILE"
fi

# --- Phase 3: Output the state of all services LAST (Summary at the bottom) ---
echo
echo -e "=============================================="
echo -e "       SERVICE STATUS OVERVIEW (On/Off)"
echo -e "=============================================="
echo
for i in "${!CHECK_NAMES[@]}"; do
    name="${CHECK_NAMES[$i]}"
    status="${CHECK_STATUSES[$i]}"
    msg="${CHECK_MESSAGES[$i]}"
    color=$GREEN
    if [ "$status" == "ERROR" ]; then color=$RED; fi
    if [ "$status" == "WARNING" ]; then color=$YELLOW; fi
    if [ "$status" == "CRITICAL" ]; then color=$RED; fi
    printf "%-35s %b\n" "$name" "${color}${status} - ${msg}${NC}"
    echo "$(date '+%F %T') ${name} ${status} - ${msg}" >> "$LOGFILE"
done

echo
echo -e "=============================================="
echo -e "       Diagnostic Complete"
echo -e "=============================================="
echo -e "Detailed log saved to: ${YELLOW}${LOGFILE}${NC}"