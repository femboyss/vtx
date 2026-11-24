# vtx - (c) 2026 34 & Claude - GPL-3.0-or-later
PREFIX  ?= /usr
DESTDIR ?=
VERSION := $(shell cat VERSION)

.PHONY: install test
install:
	install -Dm755 bin/vtx "$(DESTDIR)$(PREFIX)/bin/vtx"
	sed -i -e 's|^VTX_VERSION=""|VTX_VERSION="$(VERSION)"|' \
	       -e 's|^VTX_PREFIX=""|VTX_PREFIX="$(PREFIX)"|' "$(DESTDIR)$(PREFIX)/bin/vtx"
	install -d "$(DESTDIR)$(PREFIX)/lib/vtx"
	install -m644 lib/*.sh "$(DESTDIR)$(PREFIX)/lib/vtx/"
	install -Dm644 share/i18n/de.txt "$(DESTDIR)$(PREFIX)/share/vtx/i18n/de.txt"
	install -Dm644 completions/vtx.bash "$(DESTDIR)$(PREFIX)/share/bash-completion/completions/vtx"
	install -Dm644 completions/vtx.fish "$(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d/vtx.fish"
	install -Dm644 LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/vtx/LICENSE"
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/vtx/README.md"

test:
	bash tests/run.sh
