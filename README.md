# FreeBSD Configuration Reference (roff/groff)

A single-file roff document (`freebsd_config.ms`) containing annotated
configuration templates for a standard FreeBSD 14.x server installation,
typeset with the **groff ms** macro package.

---

## Files

```
freebsd_config.ms   — Main roff source document
README.md           — This file
```

---

## Configurations Covered

| # | File | Purpose |
|---|------|---------|
| 1 | `/boot/loader.conf` | Kernel modules, boot parameters |
| 2 | `/etc/rc.conf` | Services, networking, startup |
| 3 | `/etc/sysctl.conf` | Kernel runtime tuning |
| 4 | `/etc/resolv.conf` | DNS resolver |
| 5 | `/etc/pf.conf` | PF firewall rules |
| 6 | `/etc/ssh/sshd_config` | Hardened SSH server |
| 7 | `/etc/periodic.conf` | Daily/weekly/monthly maintenance |
| 8 | `/etc/pkg/FreeBSD.conf` | PKG repository |
| 9 | `~/.profile` / `~/.shrc` | User shell environment |

---

## Requirements

- **groff** (GNU roff) — available on most Unix-like systems
- On FreeBSD: `pkg install groff`
- On Debian/Ubuntu: `apt install groff`
- On macOS: `brew install groff`

---

## Rendering

```sh
# PDF (recommended)
groff -ms freebsd_config.ms -T pdf > freebsd_config.pdf

# PostScript → PDF (via ps2pdf)
groff -ms freebsd_config.ms | ps2pdf - freebsd_config.pdf

# Plain text (terminal preview)
groff -ms -T ascii freebsd_config.ms | less

# HTML
groff -ms -T html freebsd_config.ms > freebsd_config.html
```

---

## Customisation

Before applying any config to a live system, review and adjust:

- **Interface name** — replace `em0` with your NIC (e.g. `vtnet0`, `igb0`, `bge0`)
- **Hostname** — change `bsd01.local` in `rc.conf`
- **IP address / gateway** — update the static IP block if not using DHCP
- **SSH port** — change port `22` if desired (update `pf.conf` to match)
- **ZFS dataset** — update `vfs.root.mountfrom` in `loader.conf` if your pool name differs

---

## Security Notes

- `sshd_config` disables **password authentication** — add your public key to
  `~/.ssh/authorized_keys` before enabling `sshd`.
- `pf.conf` includes brute-force protection on SSH via the `<bruteforce>` table.
- `sysctl.conf` hides process information from other users and randomises PIDs.
- `rc.conf` disables **sendmail** entirely; install a proper MTA if mail is needed.

---

## License

Public domain. Use freely, adapt as needed.
