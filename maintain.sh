#!/bin/bash

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Configuration file not found. Please copy config.template.sh to config.sh and configure it."
    exit 1
fi

# Initialize logging
LOG_FILE="/var/log/pve-update.log"
DISCORD_BUFFER=""

# Function to log messages
log_message() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message" | tee -a "$LOG_FILE"
    DISCORD_BUFFER="${DISCORD_BUFFER}\n${message}"
}

# Function to send Discord messages
send_discord_message() {
    if [ -n "$DISCORD_WEBHOOK" ] && [ -n "$DISCORD_BUFFER" ]; then
        curl -s -H "Content-Type: application/json" -X POST \
            -d "{\"content\":\"$DISCORD_BUFFER\"}" "$DISCORD_WEBHOOK" >/dev/null
        DISCORD_BUFFER=""
    fi
}

# Function to check internet connectivity
check_internet() {
    local container=$1
    pct exec $container -- ping -c 1 -W $INTERNET_CHECK_TIMEOUT 8.8.8.8 >/dev/null 2>&1
    return $?
}

# Function to handle container errors
handle_container_error() {
    local container=$1
    local error_msg=$2
    log_message "❌ Container $container: $error_msg"
    return 0
}

# Function to update Proxmox host
update_proxmox() {
    log_message "Starting Proxmox update..."
    
    apt-get update
    if [ $? -eq 0 ]; then
        log_message "✅ APT Update"
    else
        log_message "❌ APT Update failed"
    fi

    apt-get upgrade -y
    if [ $? -eq 0 ]; then
        log_message "✅ Proxmox Update"
    else
        log_message "❌ Proxmox Update failed"
    fi

    apt-get dist-upgrade -y
    if [ $? -eq 0 ]; then
        log_message "✅ Proxmox Dist-Upgrade"
    else
        log_message "❌ Proxmox Dist-Upgrade failed"
    fi

    apt-get autoremove -y
    if [ $? -eq 0 ]; then
        log_message "✅ APT Autoremove"
    else
        log_message "❌ APT Autoremove failed"
    fi

    apt-get autoclean
    if [ $? -eq 0 ]; then
        log_message "✅ APT Autoclean"
    else
        log_message "❌ APT Autoclean failed"
    fi

    send_discord_message
}

# Function to update containers
update_containers() {
    log_message "Starting container updates..."
    
    containers=$(pct list | grep "running" | cut -f1 -d' ')
    
    for container in $containers; do
        log_message "Updating Container $container..."
        
        if ! check_internet $container; then
            log_message "⚠️ Container $container: No internet connectivity - skipping updates"
            continue
        fi
        
        is_unprivileged=$(pct config $container | grep "unprivileged: 1" || echo "")
        
        # Update repository
        if [ -n "$is_unprivileged" ]; then
            pct exec $container -- su -c "apt-get update" 2>/dev/null || handle_container_error $container "Failed to update repository"
        else
            pct exec $container -- apt-get update || handle_container_error $container "Failed to update repository"
        fi
        if [ $? -eq 0 ]; then
            log_message "✅ Container $container Update Repository"
        fi
        
        # Upgrade packages
        if [ -n "$is_unprivileged" ]; then
            pct exec $container -- su -c "apt-get upgrade -y" 2>/dev/null || handle_container_error $container "Failed to upgrade"
        else
            pct exec $container -- apt-get upgrade -y || handle_container_error $container "Failed to upgrade"
        fi
        if [ $? -eq 0 ]; then
            log_message "✅ Container $container Update"
        fi
        
        # Perform other container maintenance tasks...
        # [Previous container maintenance code continues...]

        if [ $(($(echo "$container" | cut -d' ' -f1) % 5)) -eq 0 ]; then
            send_discord_message
        fi
    done
    
    send_discord_message
}

# Function to backup containers
backup_containers() {
    log_message "Starting container backups..."
    
    if [ ! -d "$MOUNT_POINT" ]; then
        log_message "❌ Backup directory not found: $MOUNT_POINT"
        return 1
    fi

    containers=$(pct list | tail -n +2 | cut -f1 -d' ')
    
    for container in $containers; do
        log_message "📦 Backing up Container $container..."
        
        vzdump $container --compress zstd --dumpdir "$MOUNT_POINT" --mode snapshot
        if [ $? -eq 0 ]; then
            log_message "✅ Container $container backup completed"
        else
            log_message "❌ Container $container backup failed"
        fi
        
        cd "$MOUNT_POINT"
        ls -t vzdump-lxc-$container-*.tar.zst 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm
        if [ $? -eq 0 ]; then
            log_message "✅ Old backups cleaned for Container $container"
        else
            log_message "❌ Failed to clean old backups for Container $container"
        fi
    done

    send_discord_message
}

# Function to clean systemd journals
clean_journals() {
    log_message "Cleaning systemd journals..."
    journalctl --vacuum-time=7d
    if [ $? -eq 0 ]; then
        log_message "✅ Journal cleanup completed"
    else
        log_message "❌ Journal cleanup failed"
    fi
    send_discord_message
}

# Function to clean Docker images
clean_docker() {
    if command -v docker >/dev/null 2>&1; then
        log_message "Cleaning Docker images..."
        docker system prune -af
        if [ $? -eq 0 ]; then
            log_message "✅ Docker cleanup completed"
        else
            log_message "❌ Docker cleanup failed"
        fi
        send_discord_message
    fi
}

# Main execution
log_message "=== Starting maintenance at $(date) ==="
send_discord_message

update_proxmox
update_containers
backup_containers
clean_journals
clean_docker

log_message "=== Maintenance completed at $(date) ==="
send_discord_message
