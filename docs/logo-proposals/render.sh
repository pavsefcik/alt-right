#!/bin/bash
# Render every proposal to PNG (transparent) using headless Chrome, then resize with sips.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

render() { # $1 = svg path, $2 = out png, $3 = size
  local svg="$1" out="$2" size="$3"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size="$size,$size" \
    --screenshot="$out" "file://$(cd "$(dirname "$svg")" && pwd)/$(basename "$svg")" >/dev/null 2>&1
}

for dir in */[0-9][0-9]-*/; do
  dir="${dir%/}"
  render "$dir/icon.svg" "$dir/icon-1024.png" 1024
  for s in 512 256 128 64 32; do
    sips -Z "$s" "$dir/icon-1024.png" --out "$dir/icon-$s.png" >/dev/null
  done
  echo "rendered $dir"
done

# the chosen direction, refined
if [ -f final/icon.svg ]; then
  render final/icon.svg final/icon-1024.png 1024
  for s in 512 256 128 64 32 16; do
    sips -Z "$s" final/icon-1024.png --out "final/icon-$s.png" >/dev/null
  done
  for glyph in final/glyph-*.svg; do
    base="${glyph%.svg}"
    render "$glyph" "$base-1024.png" 1024
    for s in 512 256 128 64 32; do
      sips -Z "$s" "$base-1024.png" --out "$base-$s.png" >/dev/null
    done
  done
  for svg in final/variants/*.svg; do
    base="${svg%.svg}"
    render "$svg" "$base-1024.png" 1024
    for t in 256 128 64 32; do
      sips -Z "$t" "$base-1024.png" --out "$base-$t.png" >/dev/null
    done
  done
  if [ -f final/variants/01-azure.svg ]; then
    cp -f final/variants/01-azure.svg final/icon.svg
    render final/icon.svg final/icon-1024.png 1024
    for t in 512 256 128 64 32 16; do
      sips -Z "$t" final/icon-1024.png --out "final/icon-$t.png" >/dev/null
    done
  fi
  for svg in final/menubar/*.svg; do
    base="${svg%.svg}"
    render "$svg" "$base-18.png" 18
    render "$svg" "$base-36.png" 36
  done
  echo "rendered final/"
fi

for svg in menubar/*.svg; do
  render "$svg" "${svg%.svg}.png" 18
done
echo "rendered menubar"
