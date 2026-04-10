# do-snapshot — DigitalOcean Snapshot Tool for FreeBSD

A lightweight, FreeBSD-native shell script to automate DigitalOcean droplet snapshots with retention management. Built with `/bin/sh` and `fetch(1)` — no bash, no curl, no Linux dependencies.

---

## Features

- Uses FreeBSD's native `fetch(1)` — no curl or wget needed
- Full `periodic(8)` integration for unattended daily snapshots
- Auto-detects the current droplet via the DO metadata service
- Snapshot all droplets or filter by name/ID
- Configurable retention: keeps N most recent snapshots and prunes the rest
- Optional graceful shutdown before snapshot (for consistency)
- Verbose and quiet modes
- Pure POSIX `/bin/sh` — no bashisms

---

## Requirements

| Dependency | Notes |
|------------|-------|
| FreeBSD 12+ | Tested on 12, 13, 14 |
| `jq` | Install via `pkg install jq` |
| `fetch(1)` | Included in base system |
| DigitalOcean API token | Personal access token with read+write scope |

---

## Installation

```sh
# Install dependency
pkg install jq

# Download the script
fetch -o /usr/local/bin/do-snapshot \
  https://raw.githubusercontent.com/m8bsd/do-snapshot/main/do-snapshot.sh

# Make it executable
chmod +x /usr/local/bin/do-snapshot
```

---

## Usage

```
do-snapshot.sh [-t TOKEN] [-k KEEP] [-n PREFIX] [-p] [-v] [-h]
```

| Flag | Default | Description |
|------|---------|-------------|
| `-t TOKEN` | `$DO_API_TOKEN` | DigitalOcean personal access token |
| `-k KEEP` | `7` | Number of snapshots to keep per droplet |
| `-n PREFIX` | `auto` | Prefix for snapshot names |
| `-p` | off | Power off droplet before snapshot |
| `-v` | off | Verbose output |
| `-h` | — | Show help |

---

## Examples

**Snapshot the current droplet (auto-detected), keep 7:**
```sh
DO_API_TOKEN=your_token do-snapshot.sh
```

**Snapshot all droplets, keep 5, with verbose output:**
```sh
do-snapshot.sh -t your_token -k 5 -v
```

**Snapshot a specific droplet by name:**
```sh
do-snapshot.sh -t your_token web-prod-01
```

**Power off before snapshot (for filesystem consistency):**
```sh
do-snapshot.sh -t your_token -p
```

**Custom snapshot name prefix:**
```sh
do-snapshot.sh -t your_token -n backup
# Creates snapshots like: backup-web-prod-01-20240410T120000Z
```

---

## Snapshot Naming

Snapshots are named using the pattern:

```
{prefix}-{droplet-name}-{timestamp}
```

Example: `auto-web-prod-01-20240410T120000Z`

Only snapshots matching the configured prefix are counted and pruned. Snapshots created outside this tool are left untouched.

---

## Automated Daily Snapshots via periodic(8)

`do-snapshot.sh` integrates natively with FreeBSD's `periodic(8)` system.

**Step 1 — Install as a daily periodic job:**
```sh
cp do-snapshot.sh /usr/local/etc/periodic/daily/500.do-snapshot
chmod +x /usr/local/etc/periodic/daily/500.do-snapshot
```

**Step 2 — Configure via `/etc/periodic.conf`:**
```sh
# Enable the job
do_snapshot_enable="YES"

# DigitalOcean API token
DO_API_TOKEN="your_token_here"

# Number of snapshots to keep per droplet
do_snapshot_keep=7

# Snapshot name prefix
do_snapshot_prefix="auto"

# Power off before snapshot: YES or NO
do_snapshot_poweroff="NO"

# Verbose logging
do_snapshot_verbose="NO"
```

**Step 3 — Test it manually:**
```sh
/usr/local/etc/periodic/daily/500.do-snapshot
```

Periodic output is captured by `periodic(8)` and emailed to root if any output is produced (standard FreeBSD behaviour).

---

## Running on the Droplet vs. Remotely

**On the droplet itself (recommended):**
The script calls the DO metadata endpoint (`169.254.169.254`) to detect its own droplet ID automatically. No need to specify which droplet to snapshot.

**Remotely (management host):**
If the metadata endpoint is unreachable, the script falls back to listing all droplets accessible by your API token and snapshots all of them (or those matching the filter argument).

---

## Retention Policy

When the number of snapshots with the matching prefix exceeds `-k KEEP`, the oldest snapshots are deleted first until only `KEEP` remain.

Example with `-k 3` over four days:

```
Day 1: auto-web-20240407T000000Z
Day 2: auto-web-20240407T000000Z  auto-web-20240408T000000Z
Day 3: auto-web-20240407T000000Z  auto-web-20240408T000000Z  auto-web-20240409T000000Z
Day 4: auto-web-20240408T000000Z  auto-web-20240409T000000Z  auto-web-20240410T000000Z
        ^^^ Day 1 snapshot pruned
```

---

## Power-Off Mode (`-p`)

By default, snapshots are taken live (droplet keeps running). Live snapshots may capture an inconsistent filesystem state for databases or write-heavy workloads.

With `-p`, the script:
1. Sends a graceful `shutdown` action via the API
2. Waits up to 120 seconds for the droplet to reach `off` status
3. Falls back to a hard `power_off` if shutdown times out
4. Takes the snapshot
5. Powers the droplet back on

> **Note:** Power-off snapshots cause downtime. For most FreeBSD workloads, live snapshots are sufficient when combined with UFS soft-updates or ZFS.

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `DO_API_TOKEN` | DigitalOcean API token (alternative to `-t`) |
| `do_snapshot_enable` | `YES`/`NO` — used by `periodic(8)` |
| `do_snapshot_keep` | Retention count (same as `-k`) |
| `do_snapshot_prefix` | Name prefix (same as `-n`) |
| `do_snapshot_poweroff` | `YES`/`NO` — power off before snapshot |
| `do_snapshot_verbose` | `YES`/`NO` — verbose logging |

---

## Troubleshooting

**`jq: not found`**
```sh
pkg install jq
```

**`No API token`**
```sh
export DO_API_TOKEN="your_token_here"
```
Or pass it with `-t your_token_here`.

**Snapshot action times out**
The DO API can take up to 30–60 minutes for large droplets. The script polls for up to 3600 seconds (1 hour). If your droplet is very large, this is expected.

**`disabled in periodic.conf`**
Add `do_snapshot_enable="YES"` to `/etc/periodic.conf`.

**Verifying your token works:**
```sh
fetch -q -o - \
  --header "Authorization: Bearer $DO_API_TOKEN" \
  https://api.digitalocean.com/v2/account | jq .
```

---

## License

MIT — do whatever you want with it.
