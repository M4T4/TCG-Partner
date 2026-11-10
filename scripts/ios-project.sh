#!/bin/zsh
# Genera iOS/TCGPartner.xcodeproj a partir de iOS/project.yml (necesita: brew install xcodegen).
# Ábrelo con:  open iOS/TCGPartner.xcodeproj
set -euo pipefail
cd "$(dirname "$0")/../iOS"
xcodegen generate --quiet
echo "✅ iOS/TCGPartner.xcodeproj listo. Ábrelo con: open iOS/TCGPartner.xcodeproj"
