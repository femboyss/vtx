# vtx

The package manager of **Vitra**. One command for the official Arch repos,
the [vitra] repo and the AUR, plus Vitra components, repairs and platform profiles.

(c) 2026 34 & Claude. Licensed under GPL-3.0-or-later.

```
vtx                       update everything (repos + AUR)
vtx -S firefox yay-bin    install (repo packages via pacman, AUR packages get built)
vtx -Ss browser           search repos and AUR
vtx -Si vtx               package info
vtx -R firefox            remove
vtx components            all Vitra components and their status
vtx fix glassy-shell      reinstall a component and repair its config
vtx deploy                set up installed components in your home folder (runs by itself)
vtx profile windows       linux | windows | mac  (keys and mouse style)
vtx repo add              put [vitra] into /etc/pacman.conf
vtx doctor                check that everything works
vtx lang de               auto | en | de
```

Everything else that starts with `-Q`, `-F`, `-U`, `-D` or `-T` goes straight to pacman.

## Install

On Vitra it is already there. On plain Arch:

```
# 1. add the [vitra] repo (see https://femboyss.github.io/vitra-web/#/setup)
# 2.
sudo pacman -Sy vtx
```

From source:

```
git clone https://github.com/femboyss/vtx && cd vtx
sudo make install
```

## Config

`~/.config/vtx/config`:

```
LANGUAGE_UI="auto"        # auto | en | de
REVIEW_PKGBUILD="ask"     # ask | always | never
CLEAN_AFTER_BUILD="yes"   # delete AUR build folders after installing
AUR_ENABLED="yes"         # no = only pacman repos
ASSUME_YES="no"           # yes = like --noconfirm
```

## For component authors

- `/usr/share/vitra/deploy/<pkgname>.sh` (executable): the per-user setup step (copy configs
  into `~/.config` and so on). vtx runs it as the normal user, never as root:
  `install` the first time, `upgrade` when the package version changed, `fix` for `vtx fix <pkgname>`.
  vtx remembers the deployed version in `~/.local/state/vitra/deployed/<pkgname>`, so after a plain
  `pacman -Syu` the next `vtx deploy` (or `vtx deploy --quiet` at login) catches up.
- `/usr/share/vitra/profile.d/*` (executable): called with `linux`, `windows` or `mac`
  when the user runs `vtx profile ...`.
- The current profile is in `~/.config/vitra/profile` (`PROFILE="windows"`).

## Tests

```
make test
```

Runs with fake pacman/sudo/makepkg, no root needed. The AUR tests use the real AUR RPC.

---

## Deutsch

**vtx** ist der Paketmanager von Vitra: ein Befehl fuer die Arch-Repos, das [vitra]-Repo und das AUR,
dazu Vitra-Komponenten verwalten (`vtx components`), reparieren (`vtx fix`), Plattform-Profil
(`vtx profile linux|windows|mac`) und `[vitra]` in pacman.conf eintragen (`vtx repo add`).
Sprache mit `vtx lang de` umstellen, wirkt sofort.

(c) 2026 34 & Claude. Lizenz: GPL-3.0-or-later.
