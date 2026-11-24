# shellcheck shell=bash
# vtx: AUR support (RPC lookups, dependency resolution, building)
# (c) 2026 34 & Claude - GPL-3.0-or-later

AUR_BUILD_DIR="$CACHE_DIR/aur"

# aur_rpc_info name...  -> JSON array of results (one request, max ~150 names)
aur_rpc_info() {
    (( $# )) || { printf '[]'; return; }
    local q="" n
    for n in "$@"; do q+="&arg[]=$(jq -rn --arg v "$n" '$v|@uri')"; done
    curl -fsSL --max-time 20 "$AUR_URL/rpc/v5/info?${q#&}" | jq -c '.results // []'
}

# aur_rpc_search term [by]  -> JSON array
aur_rpc_search() {
    local term by=${2:-name-desc}
    term=$(jq -rn --arg v "$1" '$v|@uri')
    curl -fsSL --max-time 20 "$AUR_URL/rpc/v5/search/$term?by=$by" | jq -c '.results // []'
}

# aur_find_provider dep -> name of an AUR package that provides dep (or nothing)
aur_find_provider() {
    local dep=$1 res
    res=$(aur_rpc_search "$dep" provides 2>/dev/null) || return 1
    # prefer the package that is literally named like the dependency
    jq -r --arg d "$dep" '
        (map(select(.Name == $d)) + sort_by(-.NumVotes)) | .[0].Name // empty' <<<"$res"
}

# ---------------------------------------------------------------------------
# Dependency resolution
#
# aur_resolve pkg...  fills:
#   AUR_ORDER     pkgbases in build order (dependencies first)
#   AUR_TARGETS   assoc pkgname -> 1   (what the user asked for)
#   AUR_PKGNAMES  assoc pkgbase -> "names to install from this base"
#   AUR_ASDEP     assoc pkgname -> 1   (install --asdeps)
#   AUR_VERSION   assoc pkgname -> version in the AUR
# ---------------------------------------------------------------------------
declare -ga AUR_ORDER=()
declare -gA AUR_TARGETS=() AUR_PKGNAMES=() AUR_ASDEP=() AUR_VERSION=() _AUR_SEEN=() _AUR_BASE_DONE=()

aur_resolve() {
    AUR_ORDER=(); AUR_TARGETS=(); AUR_PKGNAMES=(); AUR_ASDEP=(); AUR_VERSION=()
    _AUR_SEEN=(); _AUR_BASE_DONE=()
    local p
    for p in "$@"; do AUR_TARGETS[$p]=1; done
    for p in "$@"; do _aur_visit "$p" 0 || return 1; done
}

_aur_visit() {
    local name=$1 asdep=$2 info base deps d dn prov
    [[ -n ${_AUR_SEEN[$name]:-} ]] && return 0
    _AUR_SEEN[$name]=1

    info=$(aur_rpc_info "$name") || { warn_f "could not reach the AUR (%s)" "$AUR_URL"; return 1; }
    if [[ $(jq length <<<"$info") -eq 0 ]]; then
        warn_f "not found in the repos or the AUR: %s" "$name"
        return 1
    fi
    base=$(jq -r '.[0].PackageBase' <<<"$info")
    AUR_VERSION[$name]=$(jq -r '.[0].Version' <<<"$info")
    (( asdep )) && AUR_ASDEP[$name]=1

    # all deps needed to build and run
    mapfile -t deps < <(jq -r '.[0] | (.Depends // []) + (.MakeDepends // []) + (.CheckDepends // []) | .[]' <<<"$info")
    for d in "${deps[@]}"; do
        dep_installed "$d" && continue
        dn=$(dep_name "$d")
        in_repos "$d" && continue          # makepkg -s installs repo deps itself
        [[ -n ${AUR_TARGETS[$dn]:-} ]] && { _aur_visit "$dn" 0 || return 1; continue; }
        if [[ -n $(aur_rpc_info "$dn" | jq -r '.[0].Name // empty') ]]; then
            _aur_visit "$dn" 1 || return 1
        else
            prov=$(aur_find_provider "$dn")
            [[ -n $prov ]] || { warn_f "nobody provides %s (needed by %s)" "$d" "$name"; return 1; }
            _aur_visit "$prov" 1 || return 1
        fi
    done

    AUR_PKGNAMES[$base]+="$name "
    if [[ -z ${_AUR_BASE_DONE[$base]:-} ]]; then
        _AUR_BASE_DONE[$base]=1
        AUR_ORDER+=("$base")
    fi
}

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

# aur_fetch base -> clones or updates $AUR_BUILD_DIR/base
aur_fetch() {
    local base=$1 dir="$AUR_BUILD_DIR/$1"
    mkdir -p "$AUR_BUILD_DIR"
    if [[ -d $dir/.git ]]; then
        git -C "$dir" fetch -q origin && git -C "$dir" reset -q --hard origin/HEAD 2>/dev/null \
            || git -C "$dir" reset -q --hard FETCH_HEAD
    else
        rm -rf "$dir"
        git clone -q "$AUR_URL/$base.git" "$dir"
    fi
}

# aur_review base -> 0 if ok to build
aur_review() {
    local base=$1 dir="$AUR_BUILD_DIR/$1"
    case $REVIEW_PKGBUILD in
        never) return 0 ;;
        ask)
            [[ -n $VTX_YES ]] && return 0
            ask "$(tf "Look at the PKGBUILD of %s before building?" "$base")" n || return 0 ;;
    esac
    local pager=${PAGER:-less}
    have "$pager" || pager="cat"
    "$pager" "$dir/PKGBUILD" </dev/tty >/dev/tty 2>&1 || true
    ask "$(tf "Build %s?" "$base")" y
}

# aur_build_install base -> builds and installs the wanted packages of base
aur_build_install() {
    local base=$1 dir="$AUR_BUILD_DIR/$1" f n name
    local -a files=() want=() deps=() main=()
    msg_f "building %s from the AUR" "$base"
    aur_fetch "$base" || die_f "could not download %s from the AUR" "$base"
    aur_review "$base" || { warn_f "skipped %s" "$base"; return 1; }

    (cd "$dir" && makepkg -s -f --needed --noconfirm) \
        || die_f "building %s failed (folder: %s)" "$base" "$dir"

    mapfile -t files < <(cd "$dir" && makepkg --packagelist 2>/dev/null)
    read -ra want <<<"${AUR_PKGNAMES[$base]}"
    for f in "${files[@]}"; do
        [[ -f $f ]] || continue
        name=$(pkgname_of_file "$f")
        for n in "${want[@]}"; do
            [[ $n == "$name" ]] || continue
            if [[ -n ${AUR_ASDEP[$n]:-} ]]; then deps+=("$f"); else main+=("$f"); fi
        done
    done
    (( ${#deps[@]} + ${#main[@]} )) || die_f "makepkg built nothing usable for %s" "$base"
    if (( ${#deps[@]} )); then
        wait_for_lock
        pac_root -U --asdeps --needed "${deps[@]}" || die_f "installing %s failed" "$base"
    fi
    if (( ${#main[@]} )); then
        wait_for_lock
        pac_root -U --needed "${main[@]}" || die_f "installing %s failed" "$base"
    fi
    [[ $CLEAN_AFTER_BUILD == yes ]] && rm -rf "$dir"
    return 0
}

# pkgname_of_file /path/foo-bar-1.2-1-x86_64.pkg.tar.zst -> foo-bar
pkgname_of_file() {
    local b=${1##*/}
    b=${b%.pkg.tar*}
    # strip -pkgver-pkgrel-arch (three dash-separated fields from the right)
    b=${b%-*}; b=${b%-*}; b=${b%-*}
    printf '%s' "$b"
}

# aur_install pkg... -> resolve + build everything in order
aur_install() {
    have git || die "git is missing: sudo pacman -S git"
    have makepkg || die "makepkg is missing: sudo pacman -S base-devel"
    (( EUID == 0 )) && [[ -z ${VTX_ALLOW_ROOT:-} ]] && die "do not build AUR packages as root, run vtx as your normal user"

    msg "resolving AUR dependencies..."
    aur_resolve "$@" || return 1

    local b names=()
    for b in "${AUR_ORDER[@]}"; do names+=("$b"); done
    printf '\n%s%s%s %s\n\n' "$C_BOLD" "$(t "AUR packages to build:")" "$C_RESET" "${names[*]}"
    ask "Continue?" y || return 1

    for b in "${AUR_ORDER[@]}"; do
        aur_build_install "$b" || return 1
    done
}

# aur_outdated -> "name local aur" lines for foreign packages with updates
aur_outdated() {
    local -a names=() vers=()
    local n v
    while read -r n v; do names+=("$n"); vers+=("$v"); done < <(pacman -Qm 2>/dev/null)
    (( ${#names[@]} )) || return 0
    local info i=0 remote
    # the RPC accepts many names at once, chunk to be nice
    while (( i < ${#names[@]} )); do
        info=$(aur_rpc_info "${names[@]:i:100}") || return 1
        local j
        for (( j = i; j < i + 100 && j < ${#names[@]}; j++ )); do
            remote=$(jq -r --arg n "${names[j]}" 'map(select(.Name == $n))[0].Version // empty' <<<"$info")
            [[ -n $remote ]] || continue
            (( $(vercmp "$remote" "${vers[j]}") > 0 )) && printf '%s %s %s\n' "${names[j]}" "${vers[j]}" "$remote"
        done
        (( i += 100 ))
    done
}
