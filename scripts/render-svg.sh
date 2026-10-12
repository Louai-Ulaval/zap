#!/bin/zsh
# render.sh in.svg out.png W H scale
U=$(mktemp -d); rm -f $2
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --user-data-dir=$U --default-background-color=00000000 --force-device-scale-factor=${5:-1} --window-size=$3,$4 --screenshot=$2 file://$1 >/dev/null 2>&1 &
P=$!; for i in {1..60}; do [[ -s $2 ]] && break; sleep 0.5; done; sleep 0.5; kill $P 2>/dev/null; pkill -f "user-data-dir=$U" 2>/dev/null; rm -rf $U
