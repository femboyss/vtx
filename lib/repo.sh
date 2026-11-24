# shellcheck shell=bash
# vtx: the [vitra] entry in pacman.conf
# (c) 2026 34 & Claude - GPL-3.0-or-later

repo_has_vitra() { grep -qE "^[[:space:]]*\[$VITRA_REPO_NAME\][[:space:]]*$" "$PACMAN_CONF" 2>/dev/null; }

repo_warn_missing() {
    repo_has_vitra && return 0
    warn "the [vitra] repo is not in pacman.conf, Vitra packages will not update. Fix: vtx repo add"
}

# the block we write, between marker comments so we can find it again
_repo_block() {
    cat <<EOF
# >>> vitra repo (managed by vtx) >>>
[$VITRA_REPO_NAME]
SigLevel = Optional TrustAll
Server = $VITRA_REPO_URL
# <<< vitra repo (managed by vtx) <<<
EOF
}

repo_add() {
    if repo_has_vitra; then
        ok "[vitra] is already in pacman.conf"
        return 0
    fi
    msg_f "adding [vitra] to %s" "$PACMAN_CONF"
    local tmp
    tmp=$(mktemp)
    cp "$PACMAN_CONF" "$tmp"
    { printf '\n'; _repo_block; } >>"$tmp"
    as_root cp "$PACMAN_CONF" "$PACMAN_CONF.vtx-backup" || die "could not back up pacman.conf"
    as_root install -m 644 "$tmp" "$PACMAN_CONF" || die "could not write pacman.conf"
    rm -f "$tmp"
    ok_f "added. Backup of the old file: %s" "$PACMAN_CONF.vtx-backup"
    wait_for_lock
    pac_root -Sy && ok "[vitra] package list downloaded"
}

repo_remove() {
    repo_has_vitra || { ok "[vitra] is not in pacman.conf"; return 0; }
    if ! grep -q '^# >>> vitra repo (managed by vtx) >>>' "$PACMAN_CONF"; then
        die_f "[vitra] was added by hand, please remove it yourself from %s" "$PACMAN_CONF"
    fi
    ask "Remove [vitra] from pacman.conf? Vitra packages will stop updating." n || return 0
    local tmp
    tmp=$(mktemp)
    sed '/^# >>> vitra repo (managed by vtx) >>>/,/^# <<< vitra repo (managed by vtx) <<</d' \
        "$PACMAN_CONF" >"$tmp"
    as_root cp "$PACMAN_CONF" "$PACMAN_CONF.vtx-backup"
    as_root install -m 644 "$tmp" "$PACMAN_CONF"
    rm -f "$tmp"
    ok "[vitra] removed from pacman.conf"
}

repo_status() {
    if repo_has_vitra; then
        ok "[vitra] is in pacman.conf"
    else
        warn "[vitra] is NOT in pacman.conf (fix: vtx repo add)"
        return 1
    fi
    local n
    n=$(pacman -Sl "$VITRA_REPO_NAME" 2>/dev/null | wc -l)
    msg_f "%s packages available in [vitra]" "$n"
    msg_f "browse them: %s" "$VITRA_WEB"
}

cmd_repo() {
    case ${1:-status} in
        add|enable)       repo_add ;;
        remove|disable)   repo_remove ;;
        status|"")        repo_status ;;
        *) die "usage: vtx repo [add|remove|status]" ;;
    esac
}
