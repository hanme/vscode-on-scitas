#!/usr/bin/env bash
# setup-laptop.sh -- run on YOUR LAPTOP (macOS, Linux, WSL) from a clone of this repo.
#
#   ./laptop/setup-laptop.sh -u <gaspar> [--no-keys]
#
# 1. creates an SSH key if you have none
# 2. writes the SCITAS hosts into ~/.ssh/config between marker lines
#    (re-running updates the block in place; a .bak is kept)
# 3. clears stale ControlMaster sockets
# 4. offers to copy your key to jed and kuma (compute nodes only accept key logins)
set -euo pipefail

GASPAR="" COPY_KEYS=1
SSH_DIR="${HOME}/.ssh"; CONFIG="${SSH_DIR}/config"
MARK_BEGIN="# >>> vscode-on-scitas (managed by setup-laptop.sh) >>>"
MARK_END="# <<< vscode-on-scitas <<<"
TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/ssh_config.template"

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
is_tty() { [[ -t 0 && -t 1 ]]; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user) GASPAR="${2:-}"; shift 2 ;;
        --no-keys) COPY_KEYS=0; shift ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done
if [[ -z "$GASPAR" ]]; then
    is_tty || die "GASPAR username required: -u <gaspar>"
    read -r -p "Your EPFL GASPAR username: " GASPAR
fi
[[ "$GASPAR" =~ ^[a-z0-9._-]+$ ]] || die "'$GASPAR' does not look like a GASPAR username"
[[ -f "$TEMPLATE" ]] || die "missing $TEMPLATE; run from a clone of the repo"

# 1. key
mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
if ! ls "$SSH_DIR"/*.pub >/dev/null 2>&1; then
    if is_tty; then say "No SSH key found; creating one"; ssh-keygen -t ed25519 -f "${SSH_DIR}/id_ed25519"
    else warn "no SSH key in ${SSH_DIR}; run: ssh-keygen -t ed25519"; fi
fi

# 2. ~/.ssh/config
say "Writing SCITAS hosts to ${CONFIG} (user: ${GASPAR})"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{ echo "$MARK_BEGIN"; sed "s/__GASPAR__/${GASPAR}/g" "$TEMPLATE"; echo "$MARK_END"; } > "$TMP/block"
touch "$CONFIG"
[[ -s "$CONFIG" ]] && cp "$CONFIG" "${CONFIG}.bak"
if grep -qF "$MARK_BEGIN" "$CONFIG"; then
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" -v f="$TMP/block" '
        index($0,b)==1 { while ((getline l < f) > 0) print l; skip=1; next }
        index($0,e)==1 && skip { skip=0; next }
        !skip { print }' "$CONFIG" > "$TMP/config.new"
    cat "$TMP/config.new" > "$CONFIG"
    echo "    updated existing block"
else
    for h in jed kuma izar helvetios jed-node kuma-node izar-node helvetios-node; do
        grep -qE "^[[:space:]]*Host[[:space:]].*(^|[[:space:]])${h}([[:space:]]|$)" "$CONFIG" \
            && warn "'Host ${h}' already exists in ${CONFIG}; the earlier entry wins, remove it"
    done
    [[ -s "$CONFIG" ]] && printf '\n' >> "$CONFIG"
    cat "$TMP/block" >> "$CONFIG"
    echo "    appended"
fi
chmod 600 "$CONFIG"

# 3. stale sockets
for h in jed kuma; do ssh -O exit "$h" >/dev/null 2>&1 || true; done
rm -f "$SSH_DIR"/cm-* 2>/dev/null || true

# 4. key to the clusters
if (( COPY_KEYS )) && is_tty && command -v ssh-copy-id >/dev/null 2>&1; then
    read -r -p "Copy your public key to jed and kuma now (password prompts follow)? [Y/n] " ans
    if [[ ! "$ans" =~ ^[Nn] ]]; then
        for h in jed kuma; do ssh-copy-id "$h" || warn "ssh-copy-id ${h} failed; ignore if you have no account there"; done
    fi
elif (( COPY_KEYS )); then
    warn "non-interactive: run later  ssh-copy-id jed; ssh-copy-id kuma"
fi

say "Done here. Next: README steps 2 (cluster) and 3 (VS Code settings)."
