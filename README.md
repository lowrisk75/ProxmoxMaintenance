# Proxmox Maintenance Script

Automated maintenance script for Proxmox VE that handles system updates, container updates, backups, and system cleaning with Discord notifications.

## Features

- 🔄 Proxmox host system updates
- 📦 LXC container updates
- 💾 Container backups with rotation
- 🧹 System journal cleaning
- 🐳 Docker cleanup (if installed)
- 📢 Discord notifications
- 🌐 Internet connectivity checks
- ⚠️ Error handling and logging

## Prerequisites

- Proxmox VE
- Bash shell
- curl
- Docker (optional)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/lowrisk75/ProxmoxMaintenance.git
cd ProxmoxMaintenance

