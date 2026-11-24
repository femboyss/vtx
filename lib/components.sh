# shellcheck shell=bash
# vtx: Vitra components (everything in [vitra]), fix, platform profile, language
# (c) 2026 34 & Claude - GPL-3.0-or-later

# vtx components [list|install|remove|reinstall] [name...]
cmd_components() {
    local sub=${1:-list}
    [[ $# -gt 0 ]] && shift
    case $sub in
        list|ls|"")          components_list ;;
        install|add)         (( $# )) || die "which component?"; wait_for_lock
                             pac_root -S --needed "${@/#/$VITRA_REPO_NAME/}" && deploy_run_pending quiet ;;
        remove|rm)           (( $# )) || die "which component?"; wait_for_lock; pac_root -Rs "$@" ;;
        reinstall|fix)       cmd_fix "$@" ;;
        *) die "usage: vtx components [list|install|remove|reinstall] [name...]" ;;
    esac
}

components_list() {
    repo_has_vitra || die "the [vitra] repo is not in pacman.conf. Fix: vtx repo add"
    local repo name ver inst local_ver status
    local -i total=0 installed=0 updates=0
    printf '%s%-28s %-16s %-16s %s%s\n' "$C_BOLD" "$(t Component)" "$(t Installed)" "$(t Available)" "$(t Status)" "$C_RESET"
    while read -r repo name ver inst; do
        (( ++total ))
        local_ver=$(pacman -Q -- "$name" 2>/dev/null | awk '{print $2}')
        if [[ -z $local_ver ]]; then
            status="${C_DIM}$(t "not installed")${C_RESET}"
            local_ver="-"
        elif (( $(vercmp "$ver" "$local_ver") > 0 )); then
            status="${C_YELLOW}$(t "update available")${C_RESET}"
            (( ++installed, ++updates ))
        else
            status="${C_GREEN}ok${C_RESET}"
            (( ++installed ))
        fi
        printf '%-28s %-16s %-16s %s\n' "$name" "$local_ver" "$ver" "$status"
    done < <(pacman -Sl "$VITRA_REPO_NAME" 2>/dev/null)
    echo
    msg_f "%s components, %s installed, %s with updates" "$total" "$installed" "$updates"
    (( total )) || msg "no packages in [vitra] yet (or run: sudo pacman -Sy)"
}

# vtx fix name... : reinstall the package, then run its setup step again
cmd_fix() {
    (( $# )) || die "fix what? Example: vtx fix glassy-shell"
    local p
    for p in "$@"; do
        pacman -Q -- "$p" >/dev/null 2>&1 || warn_f "%s is not installed, installing it" "$p"
        msg_f "reinstalling %s" "$p"
        wait_for_lock
        pac_root -S "$p" || { warn_f "could not reinstall %s" "$p"; continue; }
        deploy_one "$p" fix || continue
        ok_f "%s repaired" "$p"
    done
}

# ---------------------------------------------------------------------------
# Platform profile: linux | windows | mac
# Saved per user in ~/.config/vitra/profile. Components react through
# hooks in /usr/share/vitra/profile.d/ (called with the profile name).
# ---------------------------------------------------------------------------
PROFILE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/vitra/profile"

profile_get() {
    local p=""
    [[ -r $PROFILE_FILE ]] && p=$(sed -n 's/^PROFILE=//p' "$PROFILE_FILE" | tr -d '"')
    printf '%s' "${p:-linux}"
}

cmd_profile() {
    local want=${1:-}
    if [[ -z $want ]]; then
        msg_f "current profile: %s" "$(profile_get)"
        msg "change it with: vtx profile linux | windows | mac"
        return 0
    fi
    case $want in
        linux|windows|mac) ;;
        win) want=windows ;;
        macos|osx) want=mac ;;
        *) die "profiles: linux, windows, mac" ;;
    esac
    mkdir -p "$(dirname "$PROFILE_FILE")"
    printf 'PROFILE="%s"\n' "$want" >"$PROFILE_FILE"
    local h
    for h in /usr/share/vitra/profile.d/*; do
        [[ -x $h ]] && "$h" "$want"
    done
    ok_f "profile set to %s" "$want"
    case $want in
        windows) msg "keys: Windows key instead of Super, Ctrl+Win opens the overview, Ctrl+Esc = Windows key" ;;
        mac)     msg "keys: Command instead of Super, mac mouse icons" ;;
        linux)   msg "keys: Super, Linux defaults" ;;
    esac
}

# vtx lang [auto|en|de]
cmd_lang() {
    local want=${1:-}
    if [[ -z $want ]]; then
        msg_f "language: %s (setting: %s)" "$VTX_LANG" "$LANGUAGE_UI"
        msg "change it with: vtx lang auto | en | de"
        return 0
    fi
    case $want in auto|en|de) ;; *) die "languages: auto, en, de" ;; esac
    set_config LANGUAGE_UI "$want"
    i18n_init "$want"
    ok_f "language set to %s" "$want"
}
