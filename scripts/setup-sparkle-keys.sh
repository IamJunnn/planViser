#!/bin/bash
# Generate Sparkle EdDSA signing keys for auto-update
#
# Run this ONCE to generate your key pair:
#   ./scripts/setup-sparkle-keys.sh
#
# It will output:
#   1. A PUBLIC key  → paste into Info.plist (SUPublicEDKey)
#   2. A PRIVATE key → add as GitHub secret (SPARKLE_PRIVATE_KEY)

set -euo pipefail

DERIVED_DATA=$(xcodebuild -project Planviser.xcodeproj -scheme Planviser -showBuildSettings 2>/dev/null | grep -m 1 BUILD_DIR | awk '{print $3}' | sed 's|/Build/Products||')

GENERATE_KEYS=""
# Try to find generate_keys from SPM build artifacts
for candidate in \
  "$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" \
  "$(find ~/Library/Developer/Xcode/DerivedData -name generate_keys -path "*/Sparkle/*" 2>/dev/null | head -1)"; do
  if [ -x "$candidate" 2>/dev/null ]; then
    GENERATE_KEYS="$candidate"
    break
  fi
done

if [ -z "$GENERATE_KEYS" ]; then
  echo "Could not find Sparkle's generate_keys tool."
  echo ""
  echo "Alternative: Install Sparkle manually and use its generate_keys:"
  echo "  brew install --cask sparkle"
  echo "  /Library/Frameworks/Sparkle.framework/Resources/generate_keys"
  echo ""
  echo "Or download from: https://github.com/sparkle-project/Sparkle/releases"
  exit 1
fi

echo "=== Generating Sparkle EdDSA Key Pair ==="
echo ""
"$GENERATE_KEYS"
echo ""
echo "=== SETUP INSTRUCTIONS ==="
echo ""
echo "1. Copy the PUBLIC key and replace SPARKLE_PUBLIC_KEY_PLACEHOLDER in Planviser/Info.plist"
echo "2. Copy the PRIVATE key and add it as a GitHub secret named SPARKLE_PRIVATE_KEY"
echo "   (Go to: https://github.com/IamJunnn/planViser/settings/secrets/actions)"
echo ""
