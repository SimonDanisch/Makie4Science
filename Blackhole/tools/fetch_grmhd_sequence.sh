#!/usr/bin/env bash
# Network-only preparation: does not start Julia or touch the rendering GPU.
set -euo pipefail
asset_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../assets/grmhd" && pwd)"
base_url=https://thz.astro.illinois.edu
listing_url="$base_url/fetch_files_v3_grmhd.php?flux=MAD&spin=0"
expected_bytes=$(stat -c '%s' "$asset_dir/torus.out0.05000.h5")
listing=$(curl --fail --silent --show-error --retry 4 "$listing_url")
for index in $(seq 5001 5031); do
    printf -v name 'torus.out0.%05d.h5' "$index"
    remote_path=$(jq -er --arg name "$name" '[.[] | select(.name == $name and (.path | startswith("/v3_grmhd/MAD/a0/288x128x128/")))] | if length == 1 then .[0].path else error("Snapshot missing or ambiguous") end' <<< "$listing")
    target="$asset_dir/$name"
    if [[ -f "$target" ]]; then
        [[ $(stat -c '%s' "$target") == "$expected_bytes" ]] || { echo "Unexpected existing file size: $target" >&2; exit 1; }
        echo "Already present: $name"
        continue
    fi
    echo "Downloading $name"
    curl --fail --location --silent --show-error --retry 5 --retry-delay 3 --connect-timeout 30 --speed-limit 1024 --speed-time 120 --continue-at - --output "$target.part" "$base_url$remote_path"
    [[ $(stat -c '%s' "$target.part") == "$expected_bytes" ]] || { echo "Unexpected download size: $name" >&2; exit 1; }
    signature=$(od -An -tx1 -N8 "$target.part" | tr -d ' \n')
    [[ "$signature" == 894844460d0a1a0a ]] || { echo "Not an HDF5 file: $name" >&2; exit 1; }
    mv --no-clobber -- "$target.part" "$target"
    sha256sum "$target"
done
echo 'GRMHD sequence download complete: 05000–05031 (32 snapshots including the existing input).'
