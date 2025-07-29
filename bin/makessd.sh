#!/bin/bash

set -e

work="tmp/ssd"

mkdir -p "$work"

ssd="$1"
bins=()
shift
for prog in "$@"; do
  out="$work/$(basename "$prog" ".bbc")"
  hibasic -q -e 'SAVE "'$out'"' "$prog"
  bins+=("$out")
done

dfsimage import "$ssd" "${bins[@]}"

# vim:ts=2:sw=2:sts=2:et:ft=sh

