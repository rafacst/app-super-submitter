#!/usr/bin/env bash
#
# Takes the website screenshots: three screens, each in light and dark.
#
# It builds the package executable, not the Xcode app. The two draw the same
# SwiftUI views, and the package build needs no XcodeGen, no signing, and no
# Sparkle.
#
# The app does the awkward half. `--appearance` forces light or dark inside the
# process, so this never touches the system setting, and the app prints the
# rectangle to capture, so no shell code converts between AppKit's bottom-left
# origin and screencapture's top-left one. See Sources/SuperSubmitter/ScreenshotMode.swift.
#
# Requires: Screen Recording permission for whatever runs this. Without it
# screencapture writes a picture of the desktop wallpaper and nothing else.
#
# Usage:  tools/screenshots.sh [output-directory]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/design/screenshots}"
WORK="$(mktemp -d)"
BIN="$ROOT/.build/debug/SuperSubmitter"
SUITE="$HOME/Library/Preferences/com.rafacst.supersubmitter.screenshots.plist"

# The demo app has to be gone whichever way this exits, including a failure
# between two captures.
cleanup() {
    pkill -f "$BIN" 2>/dev/null || true
    rm -rf "$WORK"
    rm -f "$SUITE"
    defaults delete com.rafacst.supersubmitter.screenshots 2>/dev/null || true
}
trap cleanup EXIT

echo "==> Building"
swift build --package-path "$ROOT" 2>&1 | tail -3

mkdir -p "$OUT"

# The app behind the Marketing screenshot. Every value here is invented for the
# picture: no real app, no real account, no real key.
cat > "$WORK/store.yaml" <<'YAML'
version: 1

apps:
  apple:
    appId: "1234567890"
    platforms: [IOS]
    bundleId: com.example.billsplit
  google:
    packageName: com.example.billsplit

release:
  versionName: "3.2.0"

listing:
  defaultLocale: en-US
  locales:
    en-US:
      name: "Fast Bill Split"
      subtitle: "Split any bill in seconds"
      description: |
        Split a restaurant bill with your friends. No account. No ads.
      whatsNew: "Faster scanning and a new dark theme."
      keywords: "bill,split,tip,receipt,restaurant"

marketing:
  customProductPages:
    - key: students
      name: "Students"
      visible: true
      locales:
        en-US:
          promotionalText: "Split the tab without the maths."
    - key: travellers
      name: "Travellers"
      visible: true
      locales:
        en-US:
          promotionalText: "Every currency, one tap."
  experiments:
    - key: icon-2026
      name: "Rounded icon"
      trafficProportion: 40
      platform: IOS
      treatments:
        - key: rounded
          name: "Rounded"
        - key: flat
          name: "Flat"
  events:
    - key: summer-split
      badge: BADGE_LIVE_EVENT
      priority: HIGH
      purpose: APP_STORE_PROMOTION
      locales:
        en-US:
          name: "Summer split"
          shortDescription: "Share a holiday tab with the table."
          longDescription: |
            Scan the receipt, pick who had what, and send everyone their share.
  eula:
    text: |
      This licence covers the personal use of Fast Bill Split.
    territories: [USA, GBR]
YAML

# screen name, the --screenshot value, and whether it needs a linked app
capture() {
    local name="$1" screen="$2" appearance="$3" manifest="$4"
    local log="$WORK/$name.log"
    local args=(--screenshot "$screen" --appearance "$appearance")
    [ -n "$manifest" ] && args+=(--manifest "$manifest")

    # Every capture starts from nothing. The app persists the linked app and
    # the mode into its throwaway suite, so without this the welcome screen
    # after a marketing capture is not a welcome screen at all.
    defaults delete com.rafacst.supersubmitter.screenshots 2>/dev/null || true
    rm -f "$SUITE"

    "$BIN" "${args[@]}" > "$log" 2>&1 &
    local pid=$!

    # The app prints CAPTURE_RECT once its window is placed, so this waits for
    # a real signal and not for a guessed number of seconds.
    local rect="" i
    for i in $(seq 1 150); do
        rect="$(awk '/^CAPTURE_RECT /{print $2; exit}' "$log" 2>/dev/null || true)"
        [ -n "$rect" ] && break
        kill -0 "$pid" 2>/dev/null || { echo "!! the app exited early"; cat "$log"; return 1; }
        sleep 0.1
    done
    if [ -z "$rect" ]; then
        echo "!! no CAPTURE_RECT after 15s"; cat "$log"; kill "$pid" 2>/dev/null || true; return 1
    fi

    # The sheet animates in after the window is placed, and SwiftUI settles a
    # frame or two later.
    sleep 1.2
    screencapture -x -o -R"$rect" "$OUT/$name.png"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "    $name.png  ($rect)"
}

echo "==> Capturing into $OUT"
for appearance in light dark; do
    capture "welcome-$appearance"    welcome    "$appearance" ""
    capture "onboarding-$appearance" onboarding "$appearance" ""
    capture "marketing-$appearance"  marketing  "$appearance" "$WORK/store.yaml"
done

echo "==> Done"
ls -1 "$OUT"
