#!/usr/bin/env bash
set -euo pipefail

PREFIX="${HOME}/.local"
BINDIR="${PREFIX}/bin"

echo "Building bd-reminders in release mode..."
swift build -c release --disable-sandbox

mkdir -p "${BINDIR}"
cp -f .build/release/bd-reminders "${BINDIR}/bd-reminders"
chmod +x "${BINDIR}/bd-reminders"

echo "✅ Successfully installed bd-reminders to ${BINDIR}/bd-reminders"

if [[ ":$PATH:" != *":${BINDIR}:"* ]]; then
    echo ""
    echo "⚠️  Note: ${BINDIR} is not currently in your PATH."
    echo "   Add the following line to your ~/.zshrc or ~/.bashrc:"
    echo "   export PATH=\"\${HOME}/.local/bin:\$PATH\""
fi
