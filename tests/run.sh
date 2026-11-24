#!/usr/bin/env bash
# vtx test suite - runs with fake pacman/sudo/makepkg, no root needed
# (c) 2026 34 & Claude - GPL-3.0-or-later
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_CACHE_HOME="$T/home/.cache"
mkdir -p "$HOME" "$T/bin"
export LANG=C.UTF-8 NO_COLOR=1 VTX_ALLOW_ROOT=1
export VTX_PACMAN_CONF="$T/pacman.conf" VTX_PACMAN_LOCK="$T/db.lck"
export FAKE_LOG="$T/calls.log" FAKE_REPO="$T/repo.txt" FAKE_INSTALLED="$T/installed.txt"
printf '[options]\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$VTX_PACMAN_CONF"
printf 'pacman\ngit\ngo\nbase-devel\nglibc\ncurl\njq\n' >"$FAKE_REPO"
printf 'pacman 7.0.0-1\nglibc 2.40-1\nvtx 0.0.9-1\nyay 12.0.0-1\n' >"$FAKE_INSTALLED"

cat >"$T/bin/pacman" <<'P'
#!/usr/bin/env bash
echo "pacman $*" >>"$FAKE_LOG"
op=$1; shift
last=${@: -1}
case $op in
  -T) n=${last%%[<>=]*}; grep -q "^$n " "$FAKE_INSTALLED" && exit 0 || { echo "$last"; exit 127; } ;;
  -Sp) n=${last%%[<>=]*}; n=${n#*/}
       if [[ -n ${FAKE_NOT_REPO:-} ]]; then [[ " $FAKE_NOT_REPO " != *" $n "* ]]; else grep -qx "$n" "$FAKE_REPO"; fi ;;
  -Sg) exit 1 ;;
  -Q) grep "^$last " "$FAKE_INSTALLED" || exit 1 ;;
  -Qm) grep -E "^(yay|vtx) " "$FAKE_INSTALLED" ;;
  -Sl) [[ $last == vitra ]] && printf 'vitra vtx 0.1.0-1\nvitra glassy-shell 1.0.0-1\n' ;;
  *) exit 0 ;;
esac
P
printf '#!/usr/bin/env bash\necho "sudo $*" >>"$FAKE_LOG"\n"$@"\n' >"$T/bin/sudo"
cat >"$T/bin/vercmp" <<'P'
#!/usr/bin/env bash
[[ $1 == "$2" ]] && { echo 0; exit; }
[[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1) == "$1" ]] && echo 1 || echo -1
P
printf '#!/usr/bin/env bash\necho "install $*" >>"$FAKE_LOG"\n/usr/bin/install "$@"\n' >"$T/bin/install-wrap"
cat >"$T/bin/git" <<'P'
#!/usr/bin/env bash
echo "git $*" >>"$FAKE_LOG"
[[ $1 == clone || $2 == clone ]] && mkdir -p "${@: -1}" && echo "pkgname=x" >"${@: -1}/PKGBUILD"
exit 0
P
cat >"$T/bin/makepkg" <<'P'
#!/usr/bin/env bash
echo "makepkg $*" >>"$FAKE_LOG"
b=$(basename "$PWD")
if [[ $1 == --packagelist ]]; then echo "$PWD/$b-99.0-1-x86_64.pkg.tar.zst"; exit 0; fi
touch "$PWD/$b-99.0-1-x86_64.pkg.tar.zst"
P
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

VTX="$ROOT/bin/vtx"
pass=0 fail=0
check() { # check "name" condition-command...
    local name=$1; shift
    if "$@"; then pass=$((pass+1)); printf '  ok   %s\n' "$name"
    else fail=$((fail+1)); printf '  FAIL %s\n' "$name"; fi
}
contains() { grep -qF -- "$2" <<<"$1"; }

echo "== basics"
out=$("$VTX" --version); check "version" contains "$out" "vtx"
out=$("$VTX" --help);    check "help English" contains "$out" "the Vitra package manager"
out=$(LANG=de_AT.UTF-8 "$VTX" --help); check "help German via LANG" contains "$out" "der Vitra-Paketmanager"

echo "== language switch (the cmaal bug)"
out=$(LANG=de_AT.UTF-8 "$VTX" lang en); check "de system, switch to en -> English right away" contains "$out" "language set to en"
out=$(LANG=de_AT.UTF-8 "$VTX" --help);  check "en stays after restart" contains "$out" "the Vitra package manager"
out=$(LANG=C "$VTX" lang de);           check "en system, switch to de -> German right away" contains "$out" "Sprache auf de gestellt"
"$VTX" lang auto >/dev/null

echo "== repo"
out=$("$VTX" repo status 2>&1); check "status without [vitra]" contains "$out" "NOT in pacman.conf"
"$VTX" repo add >/dev/null 2>&1
check "repo add writes block" grep -q '^\[vitra\]$' "$VTX_PACMAN_CONF"
check "repo add keeps old content" grep -q '^\[core\]$' "$VTX_PACMAN_CONF"
check "backup exists" test -f "$VTX_PACMAN_CONF.vtx-backup"
"$VTX" repo add >/dev/null 2>&1
check "repo add twice = one block" test "$(grep -c '^\[vitra\]$' "$VTX_PACMAN_CONF")" -eq 1
"$VTX" -y repo remove >/dev/null 2>&1
check "repo remove (default answer no) keeps it" grep -q '^\[vitra\]$' "$VTX_PACMAN_CONF"

echo "== components / profile"
out=$("$VTX" components); check "components lists vtx update" contains "$out" "update available"
check "components lists not installed" contains "$out" "not installed"
"$VTX" profile windows >/dev/null
check "profile saved" grep -q 'PROFILE="windows"' "$XDG_CONFIG_HOME/vitra/profile"
out=$("$VTX" profile); check "profile read back" contains "$out" "windows"
"$VTX" profile banana >/dev/null 2>&1; check "bad profile rejected" test $? -ne 0

echo "== deploy (per-user setup after install)"
export VTX_DEPLOY_DIR="$T/deploy"
mkdir -p "$VTX_DEPLOY_DIR"
printf '#!/usr/bin/env bash\necho "hook $1" >>"%s/hook.log"\n' "$T" >"$VTX_DEPLOY_DIR/glassy-shell.sh"
chmod +x "$VTX_DEPLOY_DIR/glassy-shell.sh"
echo "glassy-shell 1.0-1" >>"$FAKE_INSTALLED"
"$VTX" deploy >/dev/null 2>&1
check "first deploy runs with install" grep -qx "hook install" "$T/hook.log"
check "deployed version remembered"   grep -qx "1.0-1" "$HOME/.local/state/vitra/deployed/glassy-shell"
: >"$T/hook.log"
"$VTX" deploy >/dev/null 2>&1
check "nothing to do the second time" test ! -s "$T/hook.log"
sed -i 's/^glassy-shell 1.0-1$/glassy-shell 1.1-1/' "$FAKE_INSTALLED"
"$VTX" deploy >/dev/null 2>&1
check "new version -> upgrade"        grep -qx "hook upgrade" "$T/hook.log"
: >"$T/hook.log"
"$VTX" -y fix glassy-shell >/dev/null 2>&1
check "vtx fix always deploys (fix)"  grep -qx "hook fix" "$T/hook.log"
: >"$T/hook.log"
printf 'glassy-shell\n' >>"$FAKE_REPO"
sed -i 's/^glassy-shell 1.1-1$/glassy-shell 1.2-1/' "$FAKE_INSTALLED"
"$VTX" -y -S glassy-shell >/dev/null 2>&1
check "vtx -S runs the deploy step"   grep -qx "hook upgrade" "$T/hook.log"
: >"$T/hook.log"
sed -i 's/^glassy-shell 1.2-1$/glassy-shell 1.3-1/' "$FAKE_INSTALLED"
"$VTX" -y >/dev/null 2>&1
check "vtx (update) runs the deploy step" grep -qx "hook upgrade" "$T/hook.log"

echo "== helpers"
set +u
VTX_SHARE="$ROOT/share" CONFIG_FILE=/dev/null CACHE_DIR="$T/c" PACMAN_LOCK="$VTX_PACMAN_LOCK"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/aur.sh"
check "pkgname_of_file simple"  test "$(pkgname_of_file /x/yay-12.4.2-1-x86_64.pkg.tar.zst)" = yay
check "pkgname_of_file dashes"  test "$(pkgname_of_file vitra-glassy-shell-1.0-2-any.pkg.tar.zst)" = vitra-glassy-shell
check "pkgname_of_file epoch"   test "$(pkgname_of_file foo-bar-1:2.0-1-x86_64.pkg.tar.zst)" = foo-bar
check "dep_name"                test "$(dep_name 'glassy-shell>=1.0')" = glassy-shell

echo "== AUR (real RPC)"
if curl -fsS --max-time 8 "https://aur.archlinux.org/rpc/v5/info?arg[]=yay" >/dev/null 2>&1; then
    AUR_URL=https://aur.archlinux.org
    aur_resolve yay
    check "resolve yay -> one base" test "${AUR_ORDER[*]}" = yay
    check "yay version known" test -n "${AUR_VERSION[yay]}"
    out=$("$VTX" -Si yay); check "-Si for AUR package" contains "$out" "Repository      : aur"
    out=$("$VTX" -Ss yay 2>&1); check "-Ss finds yay in AUR" contains "$out" "aur/yay "
    # pamac-aur needs libpamac-aur from the AUR: it must be built first
    export FAKE_NOT_REPO="pamac-aur libpamac-aur"
    aur_resolve pamac-aur 2>/dev/null
    check "AUR dep found" contains "${AUR_ORDER[*]}" "libpamac-aur"
    check "AUR dep built before target" test "${AUR_ORDER[${#AUR_ORDER[@]}-1]}" = pamac-aur
    check "AUR dep installed --asdeps" test -n "${AUR_ASDEP[libpamac-aur]:-}"
    unset FAKE_NOT_REPO

    echo "== install / update flow (fake makepkg)"
    printf 'pacman\ngit\ngo\nbase-devel\nglibc\ncurl\njq\nfirefox\n' >"$FAKE_REPO"
    : >"$FAKE_LOG"
    "$VTX" -y -S firefox yay-bin >"$T/out1" 2>&1
    log=$(cat "$FAKE_LOG")
    check "repo part via pacman -S"  contains "$log" "pacman -S --noconfirm --needed firefox"
    check "AUR part cloned"          contains "$log" "git clone -q https://aur.archlinux.org/yay-bin.git"
    check "AUR part built"           contains "$log" "makepkg -s -f --needed --noconfirm"
    check "AUR part installed"       contains "$log" "pacman -U --noconfirm --needed"
    : >"$FAKE_LOG"
    out=$("$VTX" -y 2>&1)
    log=$(cat "$FAKE_LOG")
    check "update runs -Syu"         contains "$log" "pacman -Syu --noconfirm"
    check "update finds old yay"     contains "$out" "yay"
    check "update rebuilds yay"      contains "$log" "aur.archlinux.org/yay.git"
    "$VTX" -S definitely-not-a-real-package-xyz >/dev/null 2>&1
    check "unknown package fails"    test $? -ne 0
else
    echo "  skip (AUR not reachable)"
fi

echo
echo "passed: $pass  failed: $fail"
(( fail == 0 ))
