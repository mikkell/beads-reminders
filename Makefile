PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

.PHONY: all build release test install uninstall clean

all: release

build:
	swift build

release:
	swift build -c release --disable-sandbox

test:
	swift test

install: release
	mkdir -p $(BINDIR)
	cp -f .build/release/bd-reminders $(BINDIR)/bd-reminders
	@echo "✅ Installed bd-reminders to $(BINDIR)/bd-reminders"

uninstall:
	rm -f $(BINDIR)/bd-reminders
	@echo "🗑️  Uninstalled bd-reminders from $(BINDIR)/bd-reminders"

clean:
	swift package clean
