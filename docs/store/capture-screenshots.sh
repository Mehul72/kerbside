#!/usr/bin/env bash
#
# Produces the App Store screenshots at 1320 x 2868 (6.9").
#
# It seeds a spot into the App Group container, then drives the real app with
# KerbsideUITests/StoreShotsTests and collects what that wrote. The sign is
# given wide hours on purpose so a plate is lit whatever time of day this runs;
# a sign outside its hours is drawn dimmed, which is correct but a poor
# advertisement.
#
#   docs/store/capture-screenshots.sh [output-directory]
#
set -euo pipefail

DEVICE="${KERBSIDE_DEVICE:-iPhone 17 Pro Max}"
OUT="${1:-docs/store/screenshots}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

UDID=$(xcrun simctl list devices available \
    | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "no simulator named $DEVICE"; exit 1; }
echo "device: $DEVICE ($UDID)"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" >/dev/null

xcodebuild -project Kerbside.xcodeproj -scheme Kerbside \
    -destination "platform=iOS Simulator,id=$UDID" build >/dev/null

APP=$(xcodebuild -project Kerbside.xcodeproj -scheme Kerbside -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Kerbside.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant location au.kerbside.Kerbside 2>/dev/null || true

# The Opera House, with the phone at the Harbour Bridge: 650 m apart.
xcrun simctl location "$UDID" set -33.8523,151.2108
xcrun simctl status_bar "$UDID" override \
    --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

SIGN=$(swift run --package-path Packages/SignKit signread --json "2P
6AM - 10PM

NO STOPPING
6AM - 10AM
MON - FRI" 2>/dev/null)

# The record is written by a watcher rather than once up front.
#
# `xcodebuild test` reinstalls the app, and reinstalling replaces the App Group
# container with a fresh empty one, so anything seeded beforehand is gone by the
# time the app reads it. This waits for the container and writes as soon as it
# appears, which lands before the app's first read. It also finds the container
# by its metadata, because `simctl get_app_container ... groups` reports nothing
# for this group even when it exists.
python3 - "$SIGN" "$UDID" <<'SEED' &
import json, sys, datetime, uuid, time, plistlib, pathlib
sign = json.loads(sys.argv[1])
base = (pathlib.Path.home() / "Library/Developer/CoreSimulator/Devices"
        / sys.argv[2] / "data/Containers/Shared/AppGroup")
now = datetime.datetime.now(datetime.timezone.utc)
parked = now - datetime.timedelta(minutes=48)
expiry = parked + datetime.timedelta(minutes=120)
stamp = lambda d: d.strftime("%Y-%m-%dT%H:%M:%SZ")

past = []
for days, note in ((1, "Level 3, bay 12"), (3, "Behind the pub"), (6, "Opposite the school")):
    at = now - datetime.timedelta(days=days, hours=2)
    past.append({
        "id": str(uuid.uuid4()), "parkedAt": stamp(at), "note": note,
        "coordinate": {"latitude": -33.86, "longitude": 151.21, "accuracy": 8},
        "sign": sign, "limit": {"openEnded": {}},
        "collectedAt": stamp(at + datetime.timedelta(hours=1, minutes=20)),
    })

record = json.dumps({
    "active": {
        "id": str(uuid.uuid4()), "parkedAt": stamp(parked),
        "coordinate": {"latitude": -33.8568, "longitude": 151.2153, "accuracy": 8},
        "note": "Level 3, bay 12", "sign": sign,
        "limit": {"expires": {"at": stamp(expiry), "source": {"sign": {"minutes": 120}}}},
    },
    "past": past,
})


def containers():
    for directory in base.glob("*/"):
        meta = directory / ".com.apple.mobile_container_manager.metadata.plist"
        try:
            if plistlib.loads(meta.read_bytes())["MCMMetadataIdentifier"] == "group.au.kerbside":
                yield directory
        except Exception:
            pass


deadline = time.time() + 300
seeded = set()
while time.time() < deadline:
    for directory in containers():
        target = directory / "parking.json"
        if directory not in seeded or not target.exists():
            target.write_text(record)
            seeded.add(directory)
            print("seeded a spot under a sign that is in force", flush=True)
    time.sleep(0.25)
SEED
SEEDER=$!
trap 'kill $SEEDER 2>/dev/null || true' EXIT

# A skipped run would otherwise hand back whatever a previous run left behind.
find "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data" \
    -type d -name kerbside-store -exec rm -rf {} + 2>/dev/null || true

xcodebuild -project Kerbside.xcodeproj -scheme Kerbside \
    -destination "platform=iOS Simulator,id=$UDID" \
    -only-testing:KerbsideUITests/StoreShotsTests test >/dev/null
kill $SEEDER 2>/dev/null || true

SHOTS=$(find "$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data" \
    -type d -name kerbside-store -exec stat -f "%m %N" {} + | sort -rn | head -1 | cut -d" " -f2-)
[ -n "$SHOTS" ] || { echo "the test wrote no screenshots"; exit 1; }

mkdir -p "$OUT"
cp "$SHOTS"/*.png "$OUT"/
xcrun simctl status_bar "$UDID" clear
echo "wrote:"
ls -1 "$OUT"
