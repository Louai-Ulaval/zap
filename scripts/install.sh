#!/bin/zsh
# Installs zap for the current user (no sudo).
#
#   ./scripts/install.sh                        picks the first AI it finds
#   ./scripts/install.sh --provider ollama --model llama3.2
#   ./scripts/install.sh --auto 1             run safe commands without asking
#   ./scripts/install.sh --uninstall

set -e

here=${0:A:h}
src=$here/zap.zsh                          # inside Zap.app
[[ -f $src ]] || src=$here/../shell/zap.zsh  # inside the repo

home=${ZAP_HOME:-$HOME/.zap}
rc=${ZDOTDIR:-$HOME}/.zshrc
begin='# >>> zap >>>'
end='# <<< zap <<<'

provider= model= uninstall= auto=
while (( $# )); do
  case $1 in
    --provider)  provider=$2; shift ;;
    --model)     model=$2; shift ;;
    --auto)      auto=$2; shift ;;
    --uninstall) uninstall=1 ;;
    *) print -u2 "unknown option: $1"; exit 1 ;;
  esac
  shift
done

remove_block() {
  [[ -f $rc ]] && sed -i '' "/^$begin\$/,/^$end\$/d" $rc
  return 0
}

if [[ -n $uninstall ]]; then
  remove_block
  rm -rf $home
  print "zap removed. Open a new Terminal window to finish."
  exit 0
fi

if [[ -z $provider ]]; then
  for p in claude codex gemini ollama; do
    (( $+commands[$p] )) && { provider=$p; break }
  done
fi
if [[ -z $provider ]]; then
  print -u2 "No AI found. Install one of: Claude Code, Codex, Gemini CLI, Ollama."
  exit 1
fi

# keep the auto-run choice from an earlier install unless told otherwise
if [[ -z $auto && -f $home/config ]]; then
  auto=$(sed -n 's/^ZAP_AUTORUN=//p' $home/config)
fi

mkdir -p $home
cp $src $home/zap.zsh
print -r -- "ZAP_PROVIDER=$provider"$'\n'"ZAP_MODEL=$model"$'\n'"ZAP_AUTORUN=${auto:-0}" > $home/config

remove_block
print -r -- "
$begin
[ -f \"\$HOME/.zap/zap.zsh\" ] && source \"\$HOME/.zap/zap.zsh\"
$end" >> $rc

print "zap installed, using $provider${model:+ ($model)}."
print "Open a new Terminal window and try:  /zap show the biggest files here"
