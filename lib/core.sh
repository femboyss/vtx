# shellcheck shell=bash
# vtx: shared helpers: config, translations, output, prompts, root
# (c) 2026 34 & Claude - GPL-3.0-or-later

# ---------------------------------------------------------------------------
# Defaults (override in ~/.config/vtx/config)
# ---------------------------------------------------------------------------
LANGUAGE_UI="auto"        # auto | en | de   (auto follows $LANG)
REVIEW_PKGBUILD="ask"     # ask | always | never  (show AUR PKGBUILDs before building)
CLEAN_AFTER_BUILD="yes"   # yes: delete AUR build folders after a successful install
AUR_ENABLED="yes"         # no: vtx only uses the pacman repos ([vitra] + Arch)
ASSUME_YES="no"           # yes: like --noconfirm for everything

# shellcheck source=/dev/null
[[ -f $CONFIG_FILE ]] && source "$CONFIG_FILE"

VTX_YES="${VTX_YES:-}"
[[ $ASSUME_YES == yes ]] && VTX_YES=1

# ---------------------------------------------------------------------------
# Translations
#   t "English"            -> German when German is on, else unchanged
#   tf "fmt %s" args...    -> printf with a translated format
# Catalog: share/i18n/<lang>.txt, "English<TAB>Translation" per line.
# ---------------------------------------------------------------------------
declare -gA _I18N=()
VTX_LANG="en"

i18n_init() {
    # always start clean, so switching de -> en at runtime really switches
    _I18N=()
    VTX_LANG="en"
    local want=${1:-$LANGUAGE_UI} k v
    if [[ $want == auto ]]; then
        case ${LC_ALL:-${LC_MESSAGES:-${LANG:-}}} in
            de*) want="de" ;;
            *)   want="en" ;;
        esac
    fi
    [[ $want == en ]] && return 0
    local file="$VTX_SHARE/i18n/$want.txt"
    [[ -r $file ]] || return 0
    while IFS=$'\t' read -r k v; do
        [[ -z $k || $k == \#* || -z $v ]] && continue
        _I18N[$k]=$v
    done <"$file"
    VTX_LANG=$want
}
i18n_init

t() {
    if [[ -n ${_I18N[$1]+x} ]]; then printf '%s' "${_I18N[$1]}"; else printf '%s' "$1"; fi
}
tf() {
    local fmt
    fmt=$(t "$1"); shift
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m' C_MAGENTA=$'\e[35m' C_CYAN=$'\e[36m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_MAGENTA="" C_CYAN=""
fi

msg()     { printf '%s::%s %s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$(t "$*")"; }
msg_f()   { local f=$1; shift; printf '%s::%s %s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$(tf "$f" "$@")"; }
ok()      { printf '%s ok%s %s\n' "$C_GREEN$C_BOLD" "$C_RESET" "$(t "$*")"; }
ok_f()    { local f=$1; shift; printf '%s ok%s %s\n' "$C_GREEN$C_BOLD" "$C_RESET" "$(tf "$f" "$@")"; }
warn()    { printf '%s%s%s %s\n' "$C_YELLOW$C_BOLD" "$(t warning:)" "$C_RESET" "$(t "$*")" >&2; }
warn_f()  { local f=$1; shift; printf '%s%s%s %s\n' "$C_YELLOW$C_BOLD" "$(t warning:)" "$C_RESET" "$(tf "$f" "$@")" >&2; }
die()     { printf '%s%s%s %s\n' "$C_RED$C_BOLD" "$(t error:)" "$C_RESET" "$(t "$*")" >&2; exit 1; }
die_f()   { local f=$1; shift; printf '%s%s%s %s\n' "$C_RED$C_BOLD" "$(t error:)" "$C_RESET" "$(tf "$f" "$@")" >&2; exit 1; }
section() { printf '\n%s==> %s%s\n' "$C_MAGENTA$C_BOLD" "$(t "$*")" "$C_RESET"; }
have()    { command -v "$1" >/dev/null 2>&1; }
has_tty() { { : </dev/tty; } 2>/dev/null; }

# ask "question" [y|n] -> 0 for yes
ask() {
    local question hint reply def=${2:-y}
    question=$(t "$1")
    [[ $def == y ]] && hint=$(t "[Y/n]") || hint=$(t "[y/N]")
    if [[ -n $VTX_YES ]] || ! has_tty; then
        [[ $def == y ]]
        return
    fi
    printf '%s::%s %s %s ' "$C_CYAN$C_BOLD" "$C_RESET" "$question" "$hint" >/dev/tty
    read -r reply </dev/tty || reply=""
    reply=${reply:-$def}
    [[ $reply =~ ^[YyJj] ]]
}

# ---------------------------------------------------------------------------
# Root / pacman
# ---------------------------------------------------------------------------
as_root() {
    if (( EUID == 0 )); then "$@"
    elif have sudo; then sudo "$@"
    elif have doas; then doas "$@"
    else die "need root: install sudo or run as root"
    fi
}

# pac_root -S foo  -> sudo pacman -S [--noconfirm] foo
pac_root() {
    local op=$1; shift
    local extra=()
    [[ -n $VTX_YES ]] && case $op in -S*|-R*|-U*) extra+=(--noconfirm) ;; esac
    as_root pacman "$op" "${extra[@]}" "$@"
}

wait_for_lock() {
    local n=0
    while [[ -e $PACMAN_LOCK ]]; do
        (( n == 0 )) && warn "pacman is busy (another install running?), waiting..."
        sleep 2
        (( ++n > 90 )) && die_f "pacman lock still there after 3 minutes: %s" "$PACMAN_LOCK"
    done
}

# strip version constraints: "foo>=1.2" -> "foo"
dep_name() { local d=${1%%[<>=]*}; printf '%s' "${d%%:*}"; }

# is the dependency already satisfied on this system?
dep_installed() { pacman -T -- "$1" >/dev/null 2>&1; }

# can the sync repos (Arch + [vitra]) provide it?
in_repos() { pacman -Sp --print-format '%n' -- "$1" >/dev/null 2>&1; }

# set_config KEY VALUE in ~/.config/vtx/config
set_config() {
    local key=$1 value=$2
    mkdir -p "$CONFIG_DIR"
    touch "$CONFIG_FILE"
    if grep -q "^$key=" "$CONFIG_FILE"; then
        sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
    else
        printf '%s="%s"\n' "$key" "$value" >>"$CONFIG_FILE"
    fi
    printf -v "$key" '%s' "$value"
}
