.\" FreeBSD Installation Configuration Document
.\" Format: groff ms macros
.\" Render with: groff -ms freebsd_config.ms > freebsd_config.ps
.\"              or: groff -ms -T pdf freebsd_config.ms > freebsd_config.pdf
.
.nr PS 11
.nr VS 13
.nr PO 1i
.nr LL 6.5i
.
.TL
FreeBSD System Configuration Reference
.AU
System Administrator
.AI
FreeBSD Installation
.DA
.AB
This document provides a reference for the core configuration files
used in a standard FreeBSD installation, including network, boot,
loader, and user environment settings.
.AE
.
.\" ====================================================
.NH 1
Loader Configuration \(em /boot/loader.conf
.PP
The loader configuration file controls boot-time kernel parameters,
module loading, and hardware tuning. Place this file at
.B /boot/loader.conf .
.PP
.DS L
.ft CW
.ps 9
# /boot/loader.conf
# Boot Loader Configuration

# --- Kernel Modules ---
geom_mirror_load="YES"       # GEOM mirror (software RAID-1)
geom_eli_load="YES"          # GEOM ELI disk encryption
zfs_load="YES"               # ZFS filesystem support
linux_load="NO"              # Linux emulation (disabled)

# --- CPU & Performance ---
kern.hz=100                  # Lower Hz for VM/low-power systems
machdep.hyperthreading_allowed=1

# --- Memory ---
vm.kmem_size="512M"
vm.kmem_size_max="1G"

# --- Verbose boot (set to 0 for quiet) ---
boot_verbose=0

# --- Serial Console (uncomment if needed) ---
# boot_serial="YES"
# comconsole_speed="115200"

# --- Filesystem ---
vfs.root.mountfrom="zfs:zroot/ROOT/default"
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
System Configuration \(em /etc/rc.conf
.PP
The primary system configuration file,
.B /etc/rc.conf ,
controls startup services, network interfaces, and system behavior.
.PP
.DS L
.ft CW
.ps 9
# /etc/rc.conf
# System Runtime Configuration

# --- Hostname ---
hostname="bsd01.local"

# --- Network Interfaces ---
# DHCP on primary interface
ifconfig_em0="DHCP"

# Static IP (alternative to DHCP)
# ifconfig_em0="inet 192.168.1.100 netmask 255.255.255.0"
# defaultrouter="192.168.1.1"

# Loopback
ifconfig_lo0="inet 127.0.0.1 netmask 255.0.0.0"

# --- IPv6 ---
ipv6_activate_all_interfaces="YES"
ifconfig_em0_ipv6="inet6 accept_rtadv"

# --- DNS ---
# Defined in /etc/resolv.conf

# --- Core Services ---
syslogd_enable="YES"
cron_enable="YES"
sendmail_enable="NONE"       # Disable sendmail
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="NO"

# --- SSH ---
sshd_enable="YES"
sshd_flags="-oUseDNS=no"

# --- NTP ---
ntpd_enable="YES"
ntpd_sync_on_start="YES"
ntpdate_enable="NO"

# --- Firewall (PF) ---
pf_enable="YES"
pf_rules="/etc/pf.conf"
pflog_enable="YES"

# --- ZFS ---
zfs_enable="YES"

# --- Power Management ---
powerd_enable="YES"
powerd_flags="-a hiadaptive -b adaptive"

# --- Dumpdev (crash dumps) ---
dumpdev="AUTO"

# --- Misc ---
clear_tmp_enable="YES"
update_motd="YES"
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
Kernel Tuning \(em /etc/sysctl.conf
.PP
.B /etc/sysctl.conf
sets kernel runtime parameters that persist across reboots.
.PP
.DS L
.ft CW
.ps 9
# /etc/sysctl.conf
# Kernel Runtime Parameters

# --- Security ---
security.bsd.see_other_uids=0        # Users cannot see other UIDs
security.bsd.see_other_gids=0        # Users cannot see other GIDs
security.bsd.unprivileged_read_msgbuf=0
kern.randompid=1                     # Randomize PIDs
net.inet.ip.random_id=1              # Randomize IP IDs

# --- Network Performance ---
net.inet.tcp.blackhole=2             # Drop TCP to closed ports silently
net.inet.udp.blackhole=1             # Drop UDP to closed ports silently
net.inet.tcp.sack.enable=1           # Enable SACK
net.inet.tcp.sendspace=65536
net.inet.tcp.recvspace=65536
kern.ipc.maxsockbuf=4194304

# --- IPv6 ---
net.inet6.ip6.accept_rtadv=1

# --- Filesystem ---
vfs.usermount=1                      # Allow users to mount filesystems
kern.maxfiles=65536
kern.maxfilesperproc=32768

# --- Shared Memory (useful for PostgreSQL etc.) ---
kern.ipc.shmmax=2147483648
kern.ipc.shmall=524288

# --- Swap ---
vm.swap_enabled=1
vm.swappiness=10
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
Network DNS \(em /etc/resolv.conf
.PP
.B /etc/resolv.conf
specifies DNS resolver settings.
.PP
.DS L
.ft CW
.ps 9
# /etc/resolv.conf
# DNS Resolver Configuration

search local home
nameserver 1.1.1.1
nameserver 1.0.0.1
nameserver 9.9.9.9
options edns0
options rotate
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
PF Firewall \(em /etc/pf.conf
.PP
The Packet Filter configuration provides stateful firewall rules.
.PP
.DS L
.ft CW
.ps 9
# /etc/pf.conf
# PF Firewall Rules

# --- Interfaces ---
ext_if = "em0"
lo_if  = "lo0"

# --- Tables ---
table <bruteforce> persist
table <rfc1918>    const { 10/8, 172.16/12, 192.168/16 }

# --- Options ---
set skip on $lo_if
set block-policy drop
set loginterface $ext_if
set optimization normal
set state-policy if-bound

scrub in all random-id fragment reassemble

# --- Default Block ---
block log all

# --- Egress (outbound) ---
pass out quick on $ext_if proto tcp  flags S/SA modulate state
pass out quick on $ext_if proto {udp icmp} keep state

# --- Ingress: Anti-spoofing ---
antispoof quick for $ext_if

# --- Ingress: Block bogons ---
block in  quick on $ext_if from <rfc1918> to any
block out quick on $ext_if from any to <rfc1918>

# --- Ingress: ICMP ---
pass in on $ext_if proto icmp icmp-type {echoreq unreach timex} keep state

# --- Ingress: SSH (brute-force protection) ---
pass in on $ext_if proto tcp to ($ext_if) port 22 \
    keep state \
    (max-src-conn 5, max-src-conn-rate 3/60, \
     overload <bruteforce> flush global)

# --- Ingress: HTTP / HTTPS ---
pass in on $ext_if proto tcp to ($ext_if) port {80 443} \
    flags S/SA synproxy state

# --- Block brute-force offenders ---
block quick from <bruteforce>
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
SSH Server \(em /etc/ssh/sshd_config
.PP
Secure Shell daemon configuration for hardened remote access.
.PP
.DS L
.ft CW
.ps 9
# /etc/ssh/sshd_config
# OpenSSH Server Configuration

Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

# --- Authentication ---
PermitRootLogin no
MaxAuthTries 4
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# --- Session ---
PrintMotd yes
PrintLastLog yes
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
MaxSessions 5

# --- Security ---
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
UseDNS no
PermitUserEnvironment no
StrictModes yes

# --- Ciphers (modern hardened set) ---
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,diffie-hellman-group16-sha512

# --- Logging ---
SyslogFacility AUTH
LogLevel VERBOSE

# --- Subsystems ---
Subsystem sftp /usr/libexec/sftp-server
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
Periodic Tasks \(em /etc/periodic.conf
.PP
.B /etc/periodic.conf
controls daily, weekly, and monthly maintenance scripts.
.PP
.DS L
.ft CW
.ps 9
# /etc/periodic.conf
# Periodic Maintenance Configuration

# --- Daily ---
daily_clean_tmps_enable="YES"
daily_clean_tmps_days=3
daily_status_security_enable="YES"
daily_status_network_enable="YES"
daily_status_uptime_enable="YES"
daily_status_df_enable="YES"
daily_show_success="NO"
daily_show_info="YES"
daily_show_badconfig="YES"

# --- Security Checks ---
daily_status_security_pkgaudit_enable="YES"

# --- Weekly ---
weekly_locate_enable="YES"
weekly_whatis_enable="YES"

# --- Monthly ---
monthly_accounting_enable="YES"

# --- Mail Reports To ---
daily_output="/var/log/daily.log"
weekly_output="/var/log/weekly.log"
monthly_output="/var/log/monthly.log"
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
Package Manager \(em /etc/pkg/FreeBSD.conf
.PP
PKG repository and package management configuration.
.PP
.DS L
.ft CW
.ps 9
# /etc/pkg/FreeBSD.conf
# PKG Repository Configuration

FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/quarterly",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
User Environment \(em ~/.profile and ~/.shrc
.PP
Shell environment configuration files for the default
.B sh
shell.
.PP
.DS L
.ft CW
.ps 9
# ~/.profile  (login shell)

# --- PATH ---
PATH=/sbin:/bin:/usr/sbin:/usr/bin
PATH=$PATH:/usr/local/sbin:/usr/local/bin
PATH=$PATH:$HOME/bin
export PATH

# --- Locale ---
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
export LANG LC_ALL

# --- Editor ---
EDITOR=vi
VISUAL=vi
export EDITOR VISUAL

# --- Pager ---
PAGER=less
LESS="-R -i --quit-if-one-screen"
export PAGER LESS

# --- History ---
HISTSIZE=10000
export HISTSIZE

# ~/.shrc  (interactive shell)
alias ls="ls -FG"
alias ll="ls -lah"
alias la="ls -A"
alias grep="grep --color=auto"
alias df="df -h"
alias du="du -sh"
alias ports="cd /usr/ports && make search"

# Prompt
PS1='[\u@\h \W]\$ '
export PS1
.ft R
.ps 11
.DE
.
.\" ====================================================
.NH 1
Rendering This Document
.PP
This document uses
.B groff
with the
.I ms
macro package. To render:
.PP
.DS L
.ft CW
.ps 9
# View as PostScript
groff -ms freebsd_config.ms | ps2pdf - freebsd_config.pdf

# View as plain text
groff -ms -T ascii freebsd_config.ms | less

# View as PDF directly (if groff is built with PDF support)
groff -ms -T pdf freebsd_config.ms > freebsd_config.pdf
.ft R
.ps 11
.DE
.PP
On FreeBSD itself, install groff via:
.ft CW
pkg install groff
.ft R
.
.\" ====================================================
.SH
Notes
.LP
All configuration files shown here are for a typical single-server
FreeBSD 14.x installation. Adapt interface names (e.g.,
.I em0 ,
.I igb0 ,
.I vtnet0 )
and IP addresses to match your hardware and network topology.
.
.\" End of document
