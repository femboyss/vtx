# shellcheck shell=bash
# vtx: doctor (system check) and help
# (c) 2026 34 & Claude - GPL-3.0-or-later

cmd_doctor() {
    local -i problems=0
    section "vtx doctor"

    _check() { # _check "label" command...
        local label=$1; shift
        if "$@" >/dev/null 2>&1; then
            printf '  %s[ ok ]%s %s\n' "$C_GREEN" "$C_RESET" "$(t "$label")"
        else
            printf '  %s[fail]%s %s\n' "$C_RED" "$C_RESET" "$(t "$label")"
            (( ++problems ))
        fi
    }

    _check "pacman is installed"                have pacman
    _check "[vitra] repo in pacman.conf"        repo_has_vitra
    _check "[vitra] package list downloaded"    test -n "$(pacman -Sl "$VITRA_REPO_NAME" 2>/dev/null | head -1)"
    _check "vitra-repo reachable on GitHub"     curl -fsSIL --max-time 10 "https://github.com/femboyss/vitra-repo"
    _check "pacman is not locked"               test ! -e "$PACMAN_LOCK"
    _check "git installed (needed for the AUR)" have git
    _check "makepkg installed (base-devel)"     have makepkg
    _check "jq installed"                       have jq
    if [[ $AUR_ENABLED == yes ]]; then
        _check "AUR reachable"                  curl -fsSL --max-time 10 "$AUR_URL/rpc/v5/info?arg[]=vtx"
    fi
    _check "not running as root"                test "$EUID" -ne 0

    # partial upgrade check: sync db newer than the last full -Syu?
    local last_syu
    last_syu=$(grep -a 'starting full system upgrade' /var/log/pacman.log 2>/dev/null | tail -1 | cut -c2-11)
    [[ -n $last_syu ]] && msg_f "last full system update: %s" "$last_syu"

    echo
    if (( problems )); then
        warn_f "%s problem(s) found" "$problems"
        repo_has_vitra || msg "fix [vitra]: vtx repo add"
        have makepkg || msg "fix base-devel: sudo pacman -S --needed base-devel"
        return 1
    fi
    ok "everything looks good"
}

cmd_help() {
    cat <<EOF
${C_BOLD}vtx${C_RESET} $VTX_VERSION  -  $(t "the Vitra package manager")
(c) 2026 34 & Claude, GPL-3.0

${C_BOLD}$(t "Packages")${C_RESET}
  vtx                       $(t "update everything (repos + AUR)")
  vtx -S <pkg>...           $(t "install from [vitra], Arch repos or the AUR")
  vtx <pkg>...              $(t "same as -S")
  vtx -R <pkg>...           $(t "remove (vtx remove = -Rs)")
  vtx -Ss <term>            $(t "search repos and AUR")
  vtx -Si <pkg>             $(t "package info")
  vtx -Q... -F... -U...     $(t "passed straight to pacman")
  vtx clean                 $(t "clean AUR build cache and old packages")

${C_BOLD}Vitra${C_RESET}
  vtx components            $(t "list all Vitra components and their status")
  vtx components install X  $(t "install a component")
  vtx components remove X   $(t "remove a component")
  vtx fix <component>       $(t "reinstall a component and repair its config")
  vtx deploy [--all]        $(t "set up components in your home folder (runs by itself)")
  vtx profile [linux|windows|mac]
                            $(t "keyboard and mouse style")
  vtx repo [add|remove|status]
                            $(t "manage [vitra] in pacman.conf")
  vtx doctor                $(t "check that everything works")
  vtx lang [auto|en|de]     $(t "language")

${C_BOLD}$(t "Options")${C_RESET}
  -y, --noconfirm           $(t "do not ask, take the default answers")
  --no-color                $(t "no colors")

$(t "Packages online:") $VITRA_WEB
EOF
}
