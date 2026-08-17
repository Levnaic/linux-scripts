#!/bin/bash

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure script is run with sudo/root (required for systemctl)
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run with sudo: sudo $0${NC}"
    exit 1
fi

# --- Find the diagnostic script ---
DIAG_SCRIPT=""
if [ -f "./lamp_diag.sh" ]; then
    DIAG_SCRIPT="./lamp_diag.sh"
elif [ -f "./lamp_diag" ]; then
    DIAG_SCRIPT="./lamp_diag"
elif command -v lamp_diag >/dev/null 2>&1; then
    DIAG_SCRIPT="lamp_diag"
fi

# Detect services
SERVICES=()

# Apache
if systemctl list-unit-files | grep -q '^apache2\.service'; then
    SERVICES+=("apache2")
fi

# MariaDB or MySQL
if systemctl list-unit-files | grep -q '^mariadb\.service'; then
    SERVICES+=("mariadb")
elif systemctl list-unit-files | grep -q '^mysql\.service'; then
    SERVICES+=("mysql")
fi

# PHP-FPM (any version)
PHPFPM=$(systemctl list-unit-files | grep -E '^php[0-9.]+-fpm\.service' | awk '{print $1}' | head -n1)
if [ -n "$PHPFPM" ]; then
    SERVICES+=("$PHPFPM")
fi

if [ ${#SERVICES[@]} -eq 0 ]; then
    echo -e "${RED}No LAMP services detected.${NC}"
    exit 1
fi

# Function to perform action on all services
manage_services() {
    local action="$1"
    local action_past="$2"
    echo -e "${YELLOW}==> ${action} all LAMP services...${NC}"
    for svc in "${SERVICES[@]}"; do
        echo -n "  ${svc}: "
        systemctl "$action" "$svc" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    done
}

# Menu loop
while true; do
    clear
    echo -e "=============================================="
    echo -e "        LAMP SERVICE MANAGER"
    echo -e "=============================================="
    echo -e "Detected services:"
    for svc in "${SERVICES[@]}"; do
        echo -e "  - ${svc}"
    done
    echo
    echo -e "Choose an action:"
    echo -e "  1) Stop all services"
    echo -e "  2) Start all services"
    echo -e "  3) Restart all services"
    if [ -n "$DIAG_SCRIPT" ]; then
        echo -e "  4) Run diagnostics (lamp_diag)"
    else
        echo -e "  4) ${RED}Diagnostics script not found!${NC}"
    fi
    echo -e "  q) Quit"
    echo
    read -p "Enter choice [1-4 or q]: " choice

    case "$choice" in
        1)
            manage_services "stop" "stopped"
            ;;
        2)
            manage_services "start" "started"
            ;;
        3)
            manage_services "restart" "restarted"
            ;;
        4)
            if [ -n "$DIAG_SCRIPT" ]; then
                echo -e "${YELLOW}Running diagnostic report...${NC}"
                sleep 1
                # Execute the diagnostic script (it will clear the screen and show its output)
                bash "$DIAG_SCRIPT"
            else
                echo -e "${RED}Diagnostic script not found in current directory or PATH.${NC}"
                echo -e "Please ensure 'lamp_diag.sh' or 'lamp_diag' is in the same folder."
            fi
            ;;
        q|Q)
            echo -e "${GREEN}Exiting.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Press Enter to continue...${NC}"
            read
            ;;
    esac

    echo
    echo -e "Press Enter to return to menu..."
    read
done