Made with ChatGPT while messing around with Cachyos 

CachyOS Samba Manager 🐧

A simple Bash-based Samba management utility for CachyOS Linux.

CachyOS Samba Manager makes it easy to install, configure and manage Samba file shares without manually editing configuration files or dealing with complicated Linux permissions.

Designed to simplify sharing folders between CachyOS and Windows computers over a local network.

✨ Features
Samba Management
Install Samba using Pacman.
Update existing Samba installation.
Automatically enable and start the Samba service.
Check Samba service status.
Validate Samba configuration using testparm.
Share Management

Create and manage three types of shares:

Share Type	Access	Permissions
Private	Authenticated user	Read / Write
Shared	Selected authenticated users	Read / Write
Public	Everyone	Read Only

Additional features:

Create new shares.
Edit and reconfigure existing shares.
Convert between Private, Shared and Public.
Automatically configure share directories.
Automatically configure Linux groups.
Set folder ownership and permissions.
Automatically enable share browsing (browseable = yes).
Preserve existing folder contents.
List configured shares and folder permissions.
User Management
Create Samba user accounts.
Configure Samba passwords.
Update existing Samba passwords.
Enable Samba accounts.
List registered Samba users.
Support existing Linux users.
Support Samba-only Linux accounts.
Firewall Management
Configure UFW rules for Samba.
Specify individual client IP addresses or trusted subnets.
Configure Samba TCP and UDP ports.
Inspect UFW firewall status.
Inspect nftables rulesets.
Diagnose multiple firewall configurations.
Windows Compatibility

Designed for straightforward access from Windows File Explorer.

Example:

text
\\192.168.2.31\Backup
\\192.168.2.31\folder


Windows can authenticate against private shares using Samba credentials, while public shares can be accessed without authentication.

🔧 Requirements
CachyOS Linux
Bash
Pacman
Samba
systemd
UFW (optional)
nftables (optional)
📦 Installation

Clone the repository:

bash
git clone https://github.com/YOUR_USERNAME/CachyOS-Samba-Manager.git


Enter the directory:

bash
cd CachyOS-Samba-Manager


Make the script executable:

bash
chmod +x Samba.sh


Run the manager:

bash
sudo ./Samba.sh

🖥️ Main Menu

The manager provides an organised menu:

text
========================================
        CACHYOS SAMBA MANAGER
                 v3.0
========================================

1. Install / update Samba

2. Firewall configuration
3. Firewall diagnostics

4. Samba configuration and status

5. Share management
6. Samba user management

7. Exit

🔐 Example Share Configuration

A typical setup might include:

Backup

Private or shared access.
Authenticated Samba users.
Read/write access.
Group-based Linux permissions.

folder

Public access.
No authentication required.
Read-only permissions.

This provides a convenient way to maintain both private storage and publicly accessible folders on the same CachyOS machine.

🛡️ Security
Private shares require authentication.
Public shares are configured as read-only.
UFW rules can be restricted to trusted client IP addresses or subnets.
Samba configuration backups are created before changes.
Configuration is validated before being applied.
Existing files are not recursively modified when changing share types.

Important: Firewall diagnostics inspect UFW and nftables independently. Additional firewall rules may need to be configured separately.

🎯 Project Goal

The goal of CachyOS Samba Manager is simple:

Make Samba installation and network folder sharing accessible to everyday CachyOS users without requiring advanced Linux administration knowledge.

Instead of manually configuring Samba, groups, folder permissions and firewall rules, users can manage their shares through one interactive Bash script.

🚀 Project Status

Version 3.0

Core functionality implemented:

Samba installation and configuration.
Private, shared and public shares.
Share editing and reconfiguration.
Samba user management.
Linux folder permission management.
UFW firewall configuration.
nftables diagnostics.
Windows network sharing.
👨‍💻 Contributing

Suggestions, improvements and bug reports are welcome.

Feel free to fork the project and contribute.

📜 License

MIT License (recommended).

CachyOS Samba Manager

Install. Configure. Share.

Making Linux file sharing easier, one folder at a time. 🐧
