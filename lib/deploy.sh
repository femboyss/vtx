# shellcheck shell=bash
# vtx: per-user deploy steps of Vitra packages
# (c) 2026 34 & Claude - GPL-3.0-or-later
#
# pacman runs as root and cannot set up a user's ~/.config. So a package can
# ship  /usr/share/vitra/deploy/<pkgname>.sh  (executable). vtx runs it as the
# normal user after every install / update of that package:
#
#   <hook> install   first time for this user
#   <hook> upgrade   the package version changed since the last deploy
#   <hook> fix       vtx fix <pkg>  (repair, always runs)
#
# Which version was deployed is remembered per user in
#   ~/.local/state/vitra/deployed/<pkgname>
# so `vtx deploy` (also run at login) catches up after a plain `pacman -Syu`.

VITRA_DEPLOY_DIR="${VTX_DEPLOY_DIR:-/usr/share/vitra/deploy}"
DEPLOY_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/vitra/deployed"

# deploy_pending -> names of packages whose deploy step has not run for the installed version
deploy_pending() {
    local hook name ver done_ver
    for hook in "$VITRA_DEPLOY_DIR"/*.sh; do
        [[ -x $hook ]] || continue
        name=$(basename "$hook" .sh)
        ver=$(pacman -Q -- "$name" 2>/dev/null | awk '{print $2}')
        [[ -n $ver ]] || continue
        done_ver=""
        [[ -r $DEPLOY_STATE/$name ]] && done_ver=$(<"$DEPLOY_STATE/$name")
        [[ $done_ver == "$ver" ]] || printf '%s\n' "$name"
    done
}

# deploy_one name mode -> runs the hook, remembers the version on success
deploy_one() {
    local name=$1 mode=$2 hook ver
    hook="$VITRA_DEPLOY_DIR/$name.sh"
    [[ -x $hook ]] || return 0
    if (( EUID == 0 )) && [[ -z ${VTX_ALLOW_ROOT:-} ]]; then
        warn_f "skipping the setup of %s for root, run vtx deploy as your normal user" "$name"
        return 0
    fi
    ver=$(pacman -Q -- "$name" 2>/dev/null | awk '{print $2}')
    msg_f "setting up %s for %s" "$name" "$USER"
    if "$hook" "$mode"; then
        mkdir -p "$DEPLOY_STATE"
        printf '%s\n' "$ver" >"$DEPLOY_STATE/$name"
        ok_f "%s is set up" "$name"
    else
        warn_f "the setup of %s reported a problem (try: vtx fix %s)" "$name" "$name"
        return 1
    fi
}

# deploy_run_pending [quiet] -> run every pending deploy step
deploy_run_pending() {
    local quiet=${1:-} name mode rc=0
    local -a todo=()
    mapfile -t todo < <(deploy_pending)
    if (( ${#todo[@]} == 0 )); then
        [[ -n $quiet ]] || ok "everything is set up"
        return 0
    fi
    for name in "${todo[@]}"; do
        mode=upgrade
        [[ -r $DEPLOY_STATE/$name ]] || mode=install
        deploy_one "$name" "$mode" || rc=1
    done
    return "$rc"
}

# vtx deploy [--quiet] [--all|pkg...]
cmd_deploy() {
    local quiet="" all="" name
    local -a pkgs=()
    for name in "$@"; do
        case $name in
            -q|--quiet) quiet=1 ;;
            -a|--all)   all=1 ;;
            *)          pkgs+=("$name") ;;
        esac
    done
    if [[ -n $all ]]; then
        rm -rf "$DEPLOY_STATE"
        deploy_run_pending "$quiet"
    elif (( ${#pkgs[@]} )); then
        for name in "${pkgs[@]}"; do
            [[ -x $VITRA_DEPLOY_DIR/$name.sh ]] || { warn_f "%s has no setup step" "$name"; continue; }
            deploy_one "$name" fix
        done
    else
        deploy_run_pending "$quiet"
    fi
}
