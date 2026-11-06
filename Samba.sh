#!/usr/bin/env bash

# ==================================================
# CACHYOS SAMBA MANAGER v3.0
# Install, configure and manage Samba shares.
# ==================================================

set -u

CONFIG="/etc/samba/smb.conf"
SHARE_ROOT="/srv/samba/shares"
BACKUP=""

# --------------------------------------------------
# GENERAL FUNCTIONS
# --------------------------------------------------

pause() {
    echo
    read -rp "Press Enter to continue..."
}

header() {
    clear
    echo "========================================"
    echo "        CACHYOS SAMBA MANAGER"
    echo "                 v3.0"
    echo "========================================"
    echo
}

backup_config() {
    BACKUP="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -p "$CONFIG" "$BACKUP"
    echo "Backup created: $BACKUP"
}

valid_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

ensure_config() {
    mkdir -p "$(dirname "$CONFIG")"
    mkdir -p "$SHARE_ROOT"

    if [[ ! -f "$CONFIG" ]]; then
        printf '[global]\n' > "$CONFIG"
    fi
}

# --------------------------------------------------
# INSTALL SAMBA
# --------------------------------------------------

install_samba() {
    echo "SAMBA INSTALLATION"
    echo

    if pacman -Q samba >/dev/null 2>&1; then
        echo "Samba is already installed."
        read -rp "Update Samba? (y/n): " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            pacman -Syu samba || return 1
        fi
    else
        read -rp "Install Samba? (y/n): " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            pacman -S samba || return 1
        else
            return
        fi
    fi

    systemctl enable --now smb
    mkdir -p "$SHARE_ROOT"

    echo
    echo "Samba installation complete."
}

# --------------------------------------------------
# SAMBA USER MANAGEMENT
# --------------------------------------------------

check_user() {
    local user="$1"

    if ! [[ "$user" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        echo "Invalid username."
        return 1
    fi

    if ! getent passwd "$user" >/dev/null; then
        echo "Linux user $user does not exist."
        read -rp "Create Samba-only Linux account? (y/n): " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            useradd -M -s /usr/bin/nologin "$user" || return 1
        else
            return 1
        fi
    fi

    if ! pdbedit -L 2>/dev/null |
        cut -d: -f1 | grep -Fxq "$user"; then

        echo "Creating Samba account..."
        smbpasswd -a "$user" || return 1
    else
        read -rp "Change Samba password? (y/n): " answer

        if [[ "$answer" =~ ^[Yy]$ ]]; then
            smbpasswd "$user" || return 1
        fi
    fi

    smbpasswd -e "$user" >/dev/null 2>&1 || true

    return 0
}

manage_users() {
    while true; do
        header
        echo "SAMBA USER MANAGEMENT"
        echo
        echo "1. List Samba users"
        echo "2. Add user / set password"
        echo "3. Change Samba password"
        echo "4. Return to main menu"
        echo

        read -rp "Choice: " choice

        case "$choice" in
            1)
                pdbedit -L
                pause
                ;;
            2)
                read -rp "Username: " user
                check_user "$user"
                pause
                ;;
            3)
                read -rp "Username: " user

                if pdbedit -L |
                    cut -d: -f1 | grep -Fxq "$user"; then
                    smbpasswd "$user"
                else
                    echo "Samba user not found."
                fi

                pause
                ;;
            4) return ;;
            *)
                echo "Invalid choice."
                pause
                ;;
        esac
    done
}

# --------------------------------------------------
# SHARE CONFIGURATION
# --------------------------------------------------

replace_share_config() {
    local share="$1"
    local path="$2"
    local type="$3"
    local group="$4"
    local tmp

    tmp=$(mktemp "${CONFIG}.XXXXXX") || return 1

    # Remove existing section without touching other shares.
    awk -v target="[$share]" '
        /^\[[^]]+\]$/ {
            skip = ($0 == target)
        }
        !skip { print }
    ' "$CONFIG" > "$tmp"

    case "$type" in
        public)
            cat >> "$tmp" <<EOF

[$share]
   path = $path
   browseable = yes
   guest ok = yes
   read only = yes
EOF
            ;;

        private|shared)
            cat >> "$tmp" <<EOF

[$share]
   path = $path
   browseable = yes
   guest ok = no
   read only = no
   valid users = @$group
   force group = $group
   create mask = 0660
   directory mask = 2770
   inherit permissions = yes
EOF
            ;;
    esac

    # Validate before replacing live configuration.
    if ! testparm -s "$tmp" >/dev/null 2>&1; then
        echo "Configuration validation failed."
        rm -f "$tmp"
        return 1
    fi

    backup_config

    if ! cp "$tmp" "$CONFIG"; then
        rm -f "$tmp"
        return 1
    fi

    chmod 0644 "$CONFIG"
    rm -f "$tmp"

    return 0
}

configure_share_users() {
    local share="$1"
    local group="smb_$share"
    local type="$2"
    local -a users=()
    local -a members=()
    local existing_members
    local user member

    if [[ "$type" == "private" ]]; then
        echo
        read -rp "Authorised username: " user
        users+=("$user")
    else
        echo
        echo "Enter authorised usernames separated by spaces:"
        read -rp "Users: " -a users
    fi

    if [[ ${#users[@]} -eq 0 ]]; then
        echo "No users supplied."
        return 1
    fi

    groupadd -f "$group" || return 1

    # Validate and configure every requested user first.
    for user in "${users[@]}"; do
        if ! valid_name "$user"; then
            echo "Invalid username: $user"
            return 1
        fi

        if ! check_user "$user"; then
            echo "Could not configure $user."
            return 1
        fi
    done

    # Remove old supplementary group memberships.
    existing_members=$(getent group "$group" | cut -d: -f4)
    IFS=',' read -ra members <<< "$existing_members"

    for member in "${members[@]}"; do
        [[ -z "$member" ]] && continue

        if [[ ! " ${users[*]} " =~ " $member " ]]; then
            gpasswd -d "$member" "$group" >/dev/null 2>&1 || true
        fi
    done

    # Add current authorised users.
    for user in "${users[@]}"; do
        usermod -aG "$group" "$user" || return 1
    done

    return 0
}

apply_share_permissions() {
    local path="$1"
    local type="$2"
    local group="$3"

    if [[ "$type" == "public" ]]; then
        chown root:root "$path" || return 1
        chmod 0755 "$path" || return 1
    else
        chown "root:$group" "$path" || return 1
        chmod 2770 "$path" || return 1
    fi
}

create_share() {
    local name path type group

    echo "CREATE NEW SHARE"
    echo

    read -rp "Share name: " name

    if ! valid_name "$name"; then
        echo "Invalid share name."
        return
    fi

    if testparm -s "$CONFIG" 2>/dev/null |
        grep -Fxq "[$name]"; then
        echo "Share already exists."
        return
    fi

    path="$SHARE_ROOT/$name"
    group="smb_$name"

    echo
    echo "SHARE TYPE"
    echo
    echo "1. Private - one authorised user"
    echo "2. Shared  - selected authorised users"
    echo "3. Public  - everyone, read only"
    echo "4. Cancel"
    echo

    read -rp "Choice: " choice

    case "$choice" in
        1) type="private" ;;
        2) type="shared" ;;
        3) type="public" ;;
        4) return ;;
        *) echo "Invalid choice."; return ;;
    esac

    mkdir -p "$path" || return 1

    if [[ "$type" != "public" ]]; then
        if ! configure_share_users "$name" "$type"; then
            echo "User configuration failed."
            return 1
        fi
    fi

    if ! replace_share_config "$name" "$path" "$type" "$group"; then
        echo "Could not configure share."
        return 1
    fi

    if ! apply_share_permissions "$path" "$type" "$group"; then
        echo "Could not set folder permissions."
        return 1
    fi

    if systemctl restart smb; then
        echo
        echo "Share created successfully!"
        echo "Name: $name"
        echo "Path: $path"
        echo "Type: $type"
        echo "Browseable: yes"
    else
        echo "Samba restart failed."
        echo "Restoring previous configuration..."
        cp "$BACKUP" "$CONFIG"
        systemctl restart smb
    fi
}

edit_share() {
    local -a shares=()
    local share path group type choice
    local i=1

    echo "EDIT EXISTING SHARE"
    echo

    while IFS= read -r share; do
        share="${share#[}"
        share="${share%]}"

        [[ "$share" == "global" ]] && continue
        [[ -n "$share" ]] && shares+=("$share")
    done < <(
        testparm -s "$CONFIG" 2>/dev/null |
        grep -E '^\[[^]]+\]$'
    )

    if [[ ${#shares[@]} -eq 0 ]]; then
        echo "No shares found."
        return
    fi

    for share in "${shares[@]}"; do
        echo "$i. $share"
        ((i++))
    done

    echo
    echo "0. Return"
    echo

    read -rp "Select share: " choice

    [[ "$choice" == "0" ]] && return

    if [[ ! "$choice" =~ ^[0-9]+$ ]] ||
       (( choice < 1 || choice > ${#shares[@]} )); then
        echo "Invalid selection."
        return
    fi

    share="${shares[$((choice-1))]}"
    path=$(testparm -s \
        --section-name="$share" \
        --parameter-name=path "$CONFIG" 2>/dev/null)

    if [[ -z "$path" || ! -d "$path" ]]; then
        echo "Share directory missing."
        return
    fi

    case "$path" in
        "$SHARE_ROOT"/*) ;;
        *)
            echo "Share is outside the managed directory."
            echo "Refusing to change its permissions."
            return
            ;;
    esac

    group="smb_$share"

    echo
    echo "Selected: $share"
    echo "Directory: $path"
    echo
    echo "NEW SHARE TYPE"
    echo
    echo "1. Private - one authorised user"
    echo "2. Shared  - selected authorised users"
    echo "3. Public  - everyone, read only"
    echo "4. Cancel"
    echo

    read -rp "Choice: " choice

    case "$choice" in
        1) type="private" ;;
        2) type="shared" ;;
        3) type="public" ;;
        4) return ;;
        *) echo "Invalid choice."; return ;;
    esac

    if [[ "$type" != "public" ]]; then
        if ! configure_share_users "$share" "$type"; then
            echo "User configuration failed."
            return 1
        fi
    fi

    echo
    echo "Share: $share"
    echo "New type: $type"
    read -rp "Apply changes? (y/n): " answer

    [[ "$answer" =~ ^[Yy]$ ]] || return

    if ! replace_share_config "$share" "$path" "$type" "$group"; then
        return 1
    fi

    if ! apply_share_permissions "$path" "$type" "$group"; then
        echo "Could not update folder permissions."
        return 1
    fi

    if systemctl restart smb; then
        echo
        echo "Share updated successfully!"
        echo "Name: $share"
        echo "Path: $path"
        echo "Type: $type"
        echo "Browseable: yes"
    else
        echo "Restart failed. Restoring configuration..."
        cp "$BACKUP" "$CONFIG"
        systemctl restart smb
    fi
}

list_shares() {
    echo "CONFIGURED SAMBA SHARES"
    echo

    testparm -s "$CONFIG" |
        grep -E '^\[.*\]$'

    echo
    echo "SHARE DIRECTORIES"
    find "$SHARE_ROOT" -mindepth 1 -maxdepth 1 \
        -type d -printf '%f\n'

    echo
    echo "FOLDER PERMISSIONS"
    find "$SHARE_ROOT" -mindepth 1 -maxdepth 1 \
        -type d -exec stat -c '%A %U:%G %n' {} \;
}

share_management() {
    while true; do
        header
        echo "SHARE MANAGEMENT"
        echo
        echo "1. Create a new share"
        echo "2. Edit / reconfigure an existing share"
        echo "3. List shares and permissions"
        echo "4. Return to main menu"
        echo

        read -rp "Choice: " choice

        case "$choice" in
            1) create_share; pause ;;
            2) edit_share; pause ;;
            3) list_shares; pause ;;
            4) return ;;
            *)
                echo "Invalid choice."
                pause
                ;;
        esac
    done
}

# --------------------------------------------------
# FIREWALL CONFIGURATION
# --------------------------------------------------

firewall_config() {
    local client

    echo "FIREWALL CONFIGURATION"
    echo
    echo "This configures Samba access through UFW."
    echo
    echo "Enter the Windows client IP or trusted subnet."
    echo "Example: 192.168.2.29"
    echo "Example: 192.168.2.0/24"
    echo

    if ! command -v ufw >/dev/null 2>&1; then
        echo "UFW is not installed."
        return
    fi

    if ! ufw status | grep -q "Status: active"; then
        echo "UFW is not active."
        echo "Enable UFW before configuring its rules."
        return
    fi

    read -rp "Client IP/subnet: " client

    if [[ -z "$client" ]]; then
        echo "No address supplied."
        return
    fi

    echo
    echo "Adding Samba firewall rules for $client..."

    ufw allow from "$client" to any port 445 proto tcp
    ufw allow from "$client" to any port 139 proto tcp
    ufw allow from "$client" to any port 137 proto udp
    ufw allow from "$client" to any port 138 proto udp

    echo
    echo "UFW rules updated."
    ufw status numbered

    echo
    echo "NOTE: nftables may have separate rules."
    echo "Use Firewall Diagnostics to inspect them."
}

# --------------------------------------------------
# FIREWALL DIAGNOSTICS
# --------------------------------------------------

firewall_diagnostics() {
    echo "FIREWALL DIAGNOSTICS"
    echo

    echo "================================="
    echo "UFW STATUS"
    echo "================================="

    if command -v ufw >/dev/null 2>&1; then
        sudo ufw status verbose
    else
        echo "UFW not installed."
    fi

    echo
    echo "================================="
    echo "NFTABLES STATUS"
    echo "================================="

    if command -v nft >/dev/null 2>&1; then
        systemctl status nftables --no-pager 2>/dev/null || true

        echo
        echo "Active nftables ruleset:"
        nft list ruleset 2>/dev/null || true
    else
        echo "nftables command not installed."
    fi

    echo
    echo "================================="
    echo "FIREWALL SERVICES"
    echo "================================="

    systemctl is-active ufw 2>/dev/null || true
    systemctl is-active nftables 2>/dev/null || true

    echo
    echo "Check for independent nftables input chains."
    echo "An additional DROP or REJECT rule can block"
    echo "Samba even when UFW allows ports 139 and 445."
}

# --------------------------------------------------
# SAMBA CONFIGURATION AND STATUS
# --------------------------------------------------

samba_status() {
    echo "SAMBA CONFIGURATION AND STATUS"
    echo

    echo "================================="
    echo "SERVICE STATUS"
    echo "================================="

    systemctl status smb --no-pager || true

    echo
    echo "================================="
    echo "CONFIGURATION VALIDATION"
    echo "================================="

    testparm -s "$CONFIG"

    echo
    echo "================================="
    echo "LISTENING PORTS"
    echo "================================="

    ss -tlnp | grep -E ':(139|445)\b' || true

    echo
    echo "================================="
    echo "SAMBA USERS"
    echo "================================="

    pdbedit -L || true
}

# --------------------------------------------------
# MAIN MENU
# --------------------------------------------------

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "Please run with sudo:"
        echo "sudo bash Samba.sh"
        exit 1
    fi

    ensure_config

    while true; do
        header

        echo "1. Install / update Samba"
        echo
        echo "2. Firewall configuration"
        echo "3. Firewall diagnostics"
        echo
        echo "4. Samba configuration and status"
        echo
        echo "5. Share management"
        echo "6. Samba user management"
        echo
        echo "7. Exit"
        echo

        read -rp "Select option: " choice

        case "$choice" in
            1) install_samba; pause ;;
            2) firewall_config; pause ;;
            3) firewall_diagnostics; pause ;;
            4) samba_status; pause ;;
            5) share_management ;;
            6) manage_users ;;
            7)
                echo
                echo "Thank you for using CachyOS Samba Manager."
                exit 0
                ;;
            *)
                echo "Invalid choice."
                pause
                ;;
        esac
    done
}

main

