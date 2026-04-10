#!/bin/sh
#
# do-snapshot.sh - DigitalOcean Droplet Snapshot Tool (FreeBSD)
#
# FreeBSD-specific: uses /bin/sh, fetch(1), sysctl, and periodic-friendly conventions.
#
# Usage:
#   do-snapshot.sh [-t TOKEN] [-k KEEP] [-n NAME_PREFIX] [-p] [-v] [-h]
#
# Options:
#   -t TOKEN        DigitalOcean API token (or set DO_API_TOKEN env var)
#   -k KEEP         Number of snapshots to keep per droplet (default: 7)
#   -n PREFIX       Snapshot name prefix (default: auto)
#   -p              Power off droplet before snapshot (live snapshots by default)
#   -v              Verbose output
#   -h              Show this help
#
# Install as periodic(8) daily job:
#   cp do-snapshot.sh /usr/local/etc/periodic/daily/500.do-snapshot
#   echo 'DO_API_TOKEN=your_token_here' >> /etc/periodic.conf
#   echo 'do_snapshot_enable="YES"'     >> /etc/periodic.conf
#   echo 'do_snapshot_keep=7'           >> /etc/periodic.conf
#
# Dependencies: fetch(1), jq (install via: pkg install jq)
#

# ---------------------------------------------------------------------------
# Default configuration (can be overridden via /etc/rc.conf or periodic.conf)
# ---------------------------------------------------------------------------
: "${DO_API_TOKEN:=}"
: "${do_snapshot_keep:=7}"
: "${do_snapshot_prefix:=auto}"
: "${do_snapshot_poweroff:=NO}"
: "${do_snapshot_verbose:=NO}"
: "${do_snapshot_enable:=YES}"

API_BASE="https://api.digitalocean.com/v2"
FETCH_CMD="/usr/bin/fetch"
FETCH_OPTS="-q -o -"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }
info()  { log "INFO:  $*"; }
err()   { log "ERROR: $*"; }
debug() { [ "${VERBOSE}" = "YES" ] && log "DEBUG: $*"; }

die() {
    err "$*"
    exit 1
}

usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^#/!d; s/^# \{0,1\}//; p }' "$0"
    exit 0
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1 — install with: pkg install $2"
}

# ---------------------------------------------------------------------------
# API helpers (uses fetch(1) — the FreeBSD native HTTP client)
# ---------------------------------------------------------------------------
api_get() {
    local endpoint="$1"
    ${FETCH_CMD} ${FETCH_OPTS} \
        --header "Authorization: Bearer ${TOKEN}" \
        --header "Content-Type: application/json" \
        "${API_BASE}${endpoint}" 2>/dev/null
}

api_post() {
    local endpoint="$1"
    local data="$2"
    ${FETCH_CMD} ${FETCH_OPTS} \
        --method POST \
        --header "Authorization: Bearer ${TOKEN}" \
        --header "Content-Type: application/json" \
        --post-data "${data}" \
        "${API_BASE}${endpoint}" 2>/dev/null
}

api_delete() {
    local endpoint="$1"
    ${FETCH_CMD} ${FETCH_OPTS} \
        --method DELETE \
        --header "Authorization: Bearer ${TOKEN}" \
        "${API_BASE}${endpoint}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Droplet helpers
# ---------------------------------------------------------------------------

# Detect the current droplet ID from the DigitalOcean metadata service.
# This works when the script runs ON the droplet itself.
get_self_droplet_id() {
    local meta
    meta=$(${FETCH_CMD} ${FETCH_OPTS} \
        "http://169.254.169.254/metadata/v1/id" 2>/dev/null)
    echo "${meta}"
}

# Fetch all droplets visible to the token (paginated).
get_all_droplets() {
    local page=1 result total
    result=""
    while :; do
        local chunk
        chunk=$(api_get "/droplets?page=${page}&per_page=100")
        local count
        count=$(echo "${chunk}" | jq '.droplets | length')
        result=$(printf '%s\n%s' "${result}" \
            "$(echo "${chunk}" | jq -c '.droplets[]')")
        total=$(echo "${chunk}" | jq '.meta.total // (.droplets | length)')
        fetched=$(echo "${result}" | grep -c '"id"' || true)
        [ "${fetched}" -ge "${total}" ] && break
        page=$((page + 1))
    done
    echo "${result}" | grep -v '^$'
}

# Fetch snapshots for a given droplet ID.
get_droplet_snapshots() {
    local droplet_id="$1"
    api_get "/droplets/${droplet_id}/snapshots?per_page=200" \
        | jq -c '.snapshots[] | select(.name | startswith("'"${SNAP_PREFIX}"'"))'
}

# Power off a droplet and wait until it reaches 'off' status.
poweroff_droplet() {
    local droplet_id="$1"
    info "Powering off droplet ${droplet_id}..."
    api_post "/droplets/${droplet_id}/actions" \
        '{"type":"shutdown"}' >/dev/null
    local status="" waited=0
    while [ "${status}" != "off" ]; do
        sleep 5
        waited=$((waited + 5))
        status=$(api_get "/droplets/${droplet_id}" \
            | jq -r '.droplet.status')
        debug "Droplet ${droplet_id} status: ${status} (${waited}s)"
        if [ "${waited}" -ge 120 ]; then
            info "Shutdown timeout — forcing power-off..."
            api_post "/droplets/${droplet_id}/actions" \
                '{"type":"power_off"}' >/dev/null
            sleep 10
            break
        fi
    done
}

# Power on a droplet.
poweron_droplet() {
    local droplet_id="$1"
    info "Powering on droplet ${droplet_id}..."
    api_post "/droplets/${droplet_id}/actions" \
        '{"type":"power_on"}' >/dev/null
}

# Trigger a snapshot action and return the action ID.
create_snapshot() {
    local droplet_id="$1"
    local snap_name="$2"
    local result action_id
    result=$(api_post "/droplets/${droplet_id}/actions" \
        "{\"type\":\"snapshot\",\"name\":\"${snap_name}\"}")
    action_id=$(echo "${result}" | jq -r '.action.id // empty')
    echo "${action_id}"
}

# Poll action status until completed or errored.
wait_for_action() {
    local droplet_id="$1"
    local action_id="$2"
    local status="" waited=0
    info "Waiting for action ${action_id} on droplet ${droplet_id}..."
    while :; do
        sleep 10
        waited=$((waited + 10))
        status=$(api_get "/droplets/${droplet_id}/actions/${action_id}" \
            | jq -r '.action.status // "unknown"')
        debug "Action ${action_id}: ${status} (${waited}s)"
        case "${status}" in
            completed) return 0 ;;
            errored)   err "Action ${action_id} failed."; return 1 ;;
        esac
        if [ "${waited}" -ge 3600 ]; then
            err "Timed out waiting for action ${action_id}"
            return 1
        fi
    done
}

# Delete old snapshots beyond the keep count.
prune_snapshots() {
    local droplet_id="$1"
    local keep="$2"

    local snaps snap_ids count excess snap_id snap_name

    # Collect snapshots sorted by created_at ascending (oldest first)
    snaps=$(api_get "/droplets/${droplet_id}/snapshots?per_page=200" \
        | jq -r "[.snapshots[] | select(.name | startswith(\"${SNAP_PREFIX}\"))] \
            | sort_by(.created_at) | .[] | [.id, .name] | @tsv")

    count=$(echo "${snaps}" | grep -c '.' || true)
    debug "Droplet ${droplet_id}: ${count} matching snapshot(s), keep=${keep}"

    if [ "${count}" -le "${keep}" ]; then
        debug "Nothing to prune."
        return 0
    fi

    excess=$((count - keep))
    info "Pruning ${excess} old snapshot(s) for droplet ${droplet_id}..."

    echo "${snaps}" | head -n "${excess}" | while IFS='	' read -r snap_id snap_name; do
        info "  Deleting snapshot: ${snap_name} (${snap_id})"
        api_delete "/snapshots/${snap_id}" >/dev/null
    done
}

# ---------------------------------------------------------------------------
# Main snapshot routine for a single droplet
# ---------------------------------------------------------------------------
snapshot_droplet() {
    local droplet_id="$1"
    local droplet_name="$2"
    local powered_off=NO

    local snap_name
    snap_name="${SNAP_PREFIX}-${droplet_name}-$(date -u '+%Y%m%dT%H%M%SZ')"
    # Replace spaces with dashes in the name
    snap_name=$(echo "${snap_name}" | tr ' ' '-')

    info "==> Droplet: ${droplet_name} (${droplet_id})"
    info "    Snapshot name: ${snap_name}"

    if [ "${POWEROFF}" = "YES" ]; then
        poweroff_droplet "${droplet_id}"
        powered_off=YES
    fi

    local action_id
    action_id=$(create_snapshot "${droplet_id}" "${snap_name}")
    if [ -z "${action_id}" ]; then
        err "Failed to initiate snapshot for droplet ${droplet_id}"
        [ "${powered_off}" = "YES" ] && poweron_droplet "${droplet_id}"
        return 1
    fi

    debug "Snapshot action ID: ${action_id}"
    wait_for_action "${droplet_id}" "${action_id}" || {
        [ "${powered_off}" = "YES" ] && poweron_droplet "${droplet_id}"
        return 1
    }

    info "    Snapshot created successfully."

    [ "${powered_off}" = "YES" ] && poweron_droplet "${droplet_id}"

    prune_snapshots "${droplet_id}" "${KEEP}"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
parse_args() {
    while getopts "t:k:n:pvh" opt; do
        case "${opt}" in
            t) TOKEN="${OPTARG}" ;;
            k) KEEP="${OPTARG}" ;;
            n) SNAP_PREFIX="${OPTARG}" ;;
            p) POWEROFF=YES ;;
            v) VERBOSE=YES ;;
            h) usage ;;
            *) usage ;;
        esac
    done
    shift $((OPTIND - 1))
    DROPLET_FILTER="$*"   # optional: specific droplet names/IDs to snapshot
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    # Merge config sources: env > periodic.conf defaults > flags
    TOKEN="${DO_API_TOKEN:-}"
    KEEP="${do_snapshot_keep}"
    SNAP_PREFIX="${do_snapshot_prefix}"
    POWEROFF="${do_snapshot_poweroff}"
    VERBOSE="${do_snapshot_verbose}"

    parse_args "$@"

    # --- Sanity checks ---
    require_cmd jq jq

    [ -z "${TOKEN}" ] && die "No API token. Set DO_API_TOKEN or use -t TOKEN."

    # Validate KEEP is a positive integer
    case "${KEEP}" in
        ''|*[!0-9]*) die "Invalid -k value: '${KEEP}' (must be a positive integer)" ;;
    esac
    [ "${KEEP}" -lt 1 ] && die "-k must be >= 1"

    info "do-snapshot starting (keep=${KEEP}, prefix=${SNAP_PREFIX}, poweroff=${POWEROFF})"

    # --- Determine target droplets ---
    local self_id
    self_id=$(get_self_droplet_id)

    if [ -n "${self_id}" ] && [ -z "${DROPLET_FILTER}" ]; then
        # Running on a droplet — only snapshot ourselves
        info "Auto-detected self droplet ID: ${self_id}"
        local self_name
        self_name=$(api_get "/droplets/${self_id}" | jq -r '.droplet.name')
        snapshot_droplet "${self_id}" "${self_name}"
    else
        # Snapshot all (or filtered) droplets accessible by the token
        info "Fetching droplet list from API..."
        local droplets
        droplets=$(get_all_droplets)

        if [ -z "${droplets}" ]; then
            info "No droplets found."
            exit 0
        fi

        echo "${droplets}" | while read -r droplet; do
            local did dname
            did=$(echo "${droplet}" | jq -r '.id')
            dname=$(echo "${droplet}" | jq -r '.name')

            # Apply optional filter
            if [ -n "${DROPLET_FILTER}" ]; then
                # shellcheck disable=SC2254
                case "${dname}" in
                    ${DROPLET_FILTER}) ;;  # matches — continue
                    *) [ "${did}" != "${DROPLET_FILTER}" ] && continue ;;
                esac
            fi

            snapshot_droplet "${did}" "${dname}" || true
        done
    fi

    info "do-snapshot done."
}

# ---------------------------------------------------------------------------
# periodic(8) compatibility: respect do_snapshot_enable from periodic.conf
# ---------------------------------------------------------------------------
if [ -f /etc/periodic.conf ]; then
    # shellcheck disable=SC1091
    . /etc/periodic.conf
fi
if [ -f /etc/periodic.conf.local ]; then
    # shellcheck disable=SC1091
    . /etc/periodic.conf.local
fi

case "${do_snapshot_enable:-NO}" in
    [Yy][Ee][Ss]) ;;
    *)
        # Only skip if we are being called by periodic(8) (no tty)
        if ! [ -t 0 ] && [ "$0" != "${0##*/}" ]; then
            echo "$(basename "$0"): disabled in periodic.conf"
            exit 0
        fi
        ;;
esac

main "$@"
