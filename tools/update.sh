#!/bin/sh
# Savage Wind updater (Linux AppImage): puts the newest release's AppImage in place of the one you have. The game
# files, game code, cache, saves and settings live in $XDG_DATA_HOME/savagewind (~/.local/share/savagewind,
# runtime/paths.c), not in the AppImage, so they are kept as they are. When the new version's game code differs, the
# start screen builds it again from the files copied already (SAVAGEWIND_AUTO_REBUILD=1): no copy, no extraction, and
# the unchanged pieces come from cache/gamecode/.
#
# usage: tools/update.sh [path/to/Savage_Wind-<version>-<arch>.AppImage]   (default: the newest one in this folder)
#   SAVAGEWIND_REPO=owner/name   another repository (default Lololegeek/SavageWindRecomp, then Revivedx/SavageWindRecomp)
#   SAVAGEWIND_STABLE=1          releases only, no pre-releases
#   SAVAGEWIND_NO_LAUNCH=1       doesn't start Savage Wind afterwards
set -eu

say() { printf '[update] %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }
command -v curl >/dev/null || die "needs curl"

arch=$(uname -m)
old=${1:-}
if [ -z "$old" ]; then
    old=$(ls -1t "$(dirname "$0")"/Savage_Wind-*-"$arch".AppImage ./Savage_Wind-*-"$arch".AppImage 2>/dev/null | head -n 1 || true)
fi
[ -n "$old" ] && [ -f "$old" ] || die "no Savage_Wind-*-$arch.AppImage found: pass its path"
dir=$(cd "$(dirname "$old")" && pwd)
cur=$(basename "$old" | sed -n "s/^Savage_Wind-\(.*\)-$arch\.AppImage$/\1/p")
say "Savage Wind ${cur:-?} in $dir"

pgrep -f "$(basename "$old")" >/dev/null 2>&1 && die "Savage Wind is running: close it first"

find_release() {  # prints "<tag> <url>" of the newest release with an AppImage for this arch
    curl -fsSL -H "Accept: application/vnd.github+json" ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        "https://api.github.com/repos/$1/releases?per_page=30" 2>/dev/null |
    python3 -c '
import json, sys
stable, arch = sys.argv[1] == "1", sys.argv[2]
for r in json.load(sys.stdin):
    if r.get("draft") or (stable and r.get("prerelease")): continue
    for a in r.get("assets", []):
        if a["name"].startswith("Savage_Wind-") and a["name"].endswith("-" + arch + ".AppImage"):
            print(r["tag_name"].lstrip("vV"), a["browser_download_url"]); sys.exit(0)
' "${SAVAGEWIND_STABLE:-0}" "$arch" || true
}
rel=""
for repo in ${SAVAGEWIND_REPO:-Lololegeek/SavageWindRecomp Revivedx/SavageWindRecomp}; do
    rel=$(find_release "$repo"); [ -n "$rel" ] && break
done
[ -n "$rel" ] || die "no $arch AppImage release found"
tag=${rel%% *}; url=${rel#* }
if [ "$tag" = "$cur" ]; then
    say "already up to date ($tag)"
else
    new="$dir/$(basename "$url")"
    say "downloading $tag: $url"
    curl -fL --progress-bar -o "$new.part" "$url"
    chmod +x "$new.part" && mv "$new.part" "$new"
    [ "$new" != "$dir/$(basename "$old")" ] && mv "$old" "$old.old" && say "the old one is kept as $(basename "$old").old"
    old=$new
    say "updated: ${cur:-?} -> $tag"
fi
if [ -z "${SAVAGEWIND_NO_LAUNCH:-}" ]; then
    SAVAGEWIND_AUTO_REBUILD=1 nohup "$old" >/dev/null 2>&1 &
fi
