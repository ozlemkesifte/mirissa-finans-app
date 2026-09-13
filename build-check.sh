#!/bin/zsh
# Tüm kaynak kodu macOS SDK'sı üzerinden derler — Xcode gerekmez.
set -e
cd "${0:a:h}/MirissaKit"
exec swift build "$@"
