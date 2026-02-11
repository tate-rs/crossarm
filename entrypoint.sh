#!/usr/bin/env bash
set -e

for f in /etc/profile.d/*.sh; do
  [ -r "$f" ] && source "$f"
done

if [ $# -eq 0 ]; then
  exec bash -i
else
  exec bash -i -c "$*"
fi