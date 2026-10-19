#!/bin/zsh
# Ejecuta los tests. Con solo las Command Line Tools (sin Xcode) hay que
# indicar dónde está el framework Testing.
set -e
cd "$(dirname "$0")/.."
DEV=$(xcode-select -p)
if [[ "$DEV" == *CommandLineTools* ]]; then
  F="$DEV/Library/Developer/Frameworks"
  L="$DEV/Library/Developer/usr/lib"
  exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L" "$@"
fi
exec swift test "$@"
