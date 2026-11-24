# shellcheck shell=bash
# vtx: install, update, remove, search, info
# (c) 2026 34 & Claude - GPL-3.0-or-later

# vtx / vtx -Syu : full system update (repos + AUR)
cmd_update() {
    local extra=("$@")
    repo_warn_missing
    section "Updating packages from the repos"
    wait_for_lock
    pac_root -Syu "${extra[@]}" || die "the system update failed, nothing from the AUR was touched"
    deploy_run_pending quiet

    [[ $AUR_ENABLED == yes ]] || { ok "system is up to date"; return 0; }

    section "Checking AUR packages"
    local lines n=()
    lines=$(aur_outdated) || { warn "could not reach the AUR, skipped AUR updates"; return 0; }
    if [[ -z $lines ]]; then
        ok "system is up to date"
        return 0
    fi
    local name old new
    while read -r name old new; do
        printf '   %-30s %s%s%s -> %s%s%s\n' "$name" "$C_RED" "$old" "$C_RESET" "$C_GREEN" "$new" "$C_RESET"
        n+=("$name")
    done <<<"$lines"
    echo
    ask "$(tf "Update %s AUR package(s)?" "${#n[@]}")" y || return 0
    aur_install "${n[@]}" && deploy_run_pending quiet && ok "system is up to date"
}

# split names into repo packages and AUR packages
# fills REPO_PKGS and AUR_PKGS
_split_targets() {
    REPO_PKGS=(); AUR_PKGS=()
    local p
    for p in "$@"; do
        if in_repos "$p" || pacman -Sg -- "$p" >/dev/null 2>&1; then
            REPO_PKGS+=("$p")
        elif [[ $AUR_ENABLED == yes && $p != */* ]]; then
            AUR_PKGS+=("$p")
        else
            die_f "package not found: %s" "$p"
        fi
    done
}
declare -ga REPO_PKGS=() AUR_PKGS=()

# vtx -S pkg... / vtx install pkg...
cmd_install() {
    local flags=() names=() a
    for a in "$@"; do
        if [[ $a == -* ]]; then flags+=("$a"); else names+=("$a"); fi
    done
    (( ${#names[@]} )) || die "what should I install? Example: vtx -S firefox"

    _split_targets "${names[@]}"
    if (( ${#REPO_PKGS[@]} )); then
        wait_for_lock
        pac_root -S --needed "${flags[@]}" "${REPO_PKGS[@]}" || die "installing from the repos failed"
    fi
    if (( ${#AUR_PKGS[@]} )); then
        aur_install "${AUR_PKGS[@]}" || die "installing from the AUR failed"
    fi
    deploy_run_pending quiet
    ok_f "installed: %s" "${names[*]}"
}

# vtx -Sw foo, vtx -Sdd foo ... : extra pacman flags glued to -S
cmd_install_flags() {
    local op=$1; shift
    cmd_install "-${op#-S}" "$@"
}

# vtx -Ss term
cmd_search() {
    (( $# )) || die "search for what? Example: vtx -Ss browser"
    local color=(--color never)
    [[ -n $C_RESET ]] && color=(--color always)
    pacman -Ss "${color[@]}" -- "$@"
    [[ $AUR_ENABLED == yes ]] || return 0

    local res
    res=$(aur_rpc_search "$*" 2>/dev/null) || { warn "could not reach the AUR"; return 0; }
    jq -r '
        sort_by(-.NumVotes) | .[:40][] |
        [.Name, .Version, (.NumVotes|tostring), (.Popularity*100|floor/100|tostring),
         (if .OutOfDate then "1" else "0" end), (.Description // "")] | @tsv' <<<"$res" |
    while IFS=$'\t' read -r name ver votes pop ood desc; do
        local inst=""
        pacman -Q -- "$name" >/dev/null 2>&1 && inst=" ${C_CYAN}[$(t installed)]${C_RESET}"
        local o=""
        [[ $ood == 1 ]] && o=" ${C_RED}($(t "out of date"))${C_RESET}"
        printf '%saur/%s%s %s%s%s %s(+%s %s)%s%s%s\n    %s\n' \
            "$C_MAGENTA$C_BOLD" "$C_RESET$C_BOLD" "$name" "$C_GREEN" "$ver" "$C_RESET" \
            "$C_DIM" "$votes" "$pop" "$C_RESET" "$inst" "$o" "$desc"
    done
}

# vtx -Si pkg
cmd_info() {
    (( $# )) || die "info about what? Example: vtx -Si vtx"
    local p info
    for p in "$@"; do
        if in_repos "$p"; then
            pacman -Si -- "$p"
            continue
        fi
        info=$(aur_rpc_info "$p" 2>/dev/null) || { warn "could not reach the AUR"; continue; }
        if [[ $(jq length <<<"$info") -eq 0 ]]; then
            warn_f "package not found: %s" "$p"
            continue
        fi
        jq -r --arg url "$AUR_URL" '.[0] |
            "Repository      : aur",
            "Name            : \(.Name)",
            "Version         : \(.Version)",
            "Description     : \(.Description // "")",
            "URL             : \(.URL // "")",
            "AUR URL         : \($url)/packages/\(.Name)",
            "Licenses        : \((.License // []) | join("  "))",
            "Depends On      : \((.Depends // ["None"]) | join("  "))",
            "Make Deps       : \((.MakeDepends // ["None"]) | join("  "))",
            "Maintainer      : \(.Maintainer // "orphan")",
            "Votes           : \(.NumVotes)",
            "Popularity      : \(.Popularity)",
            "Out Of Date     : \(if .OutOfDate then "Yes" else "No" end)",
            "Last Modified   : \(.LastModified | todate)",
            ""' <<<"$info"
    done
}

# vtx -R pkg / vtx remove pkg
cmd_remove() {
    local op=$1; shift
    [[ $op == -R* ]] || op="-Rs"
    (( $# )) || die "remove what? Example: vtx -R firefox"
    wait_for_lock
    pac_root "$op" "$@"
}

# -Q, -F, -T: no root needed (except -Fy); -D, -U: root
cmd_passthrough() {
    local op=$1; shift
    case $op in
        -Q*|-T*)         pacman "$op" "$@" ;;
        -F*y*)           as_root pacman "$op" "$@" ;;
        -F*)             pacman "$op" "$@" ;;
        -D*|-U*)         wait_for_lock; pac_root "$op" "$@" ;;
    esac
}

# vtx clean: AUR build cache + old package versions
cmd_clean() {
    local size="0"
    [[ -d $AUR_BUILD_DIR ]] && size=$(du -sh "$AUR_BUILD_DIR" 2>/dev/null | cut -f1)
    if ask "$(tf "Delete the AUR build cache (%s)?" "$size")" y; then
        rm -rf "$AUR_BUILD_DIR"
        ok "AUR build cache deleted"
    fi
    if have paccache; then
        ask "Remove old package versions from the pacman cache (keep the last 2)?" y \
            && as_root paccache -rk2
    else
        msg "tip: install pacman-contrib for paccache (cleans the pacman cache)"
    fi
}
