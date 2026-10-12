# zap — say what you want in plain words, get the command, run it.
#
# Loaded from ~/.zshrc. Type `/zap <what you want>` at the prompt.

ZAP_VERSION=0.1.0
ZAP_HOME=${ZAP_HOME:-$HOME/.zap}

zap() {
  emulate -L zsh
  setopt extended_glob no_monitor no_notify local_traps

  local ZAP_PROVIDER ZAP_MODEL ZAP_AUTORUN
  [[ -r $ZAP_HOME/config ]] && source $ZAP_HOME/config
  ZAP_PROVIDER=${ZAP_PROVIDER:-claude}

  local _b= _d= _r= _y= _g= _x=
  if [[ -t 1 ]]; then
    _b=$'\e[1m' _d=$'\e[2m' _r=$'\e[31m' _y=$'\e[33m' _g=$'\e[32m' _x=$'\e[0m'
  fi

  # the /zap key binding passes everything as one quoted word
  (( $# == 1 )) && [[ $1 == -* ]] && set -- ${(z)1}

  case $1 in
    ''|-h|--help) _zap_flash_show wink; _zap_help; return ;;
    -v|--version) print "zap $ZAP_VERSION, using $ZAP_PROVIDER${ZAP_MODEL:+ ($ZAP_MODEL)}"; return ;;
    --use)        _zap_use $2 $3; return ;;
    --auto)       _zap_auto $2; return ;;
    --history)    [[ -f $ZAP_HOME/history ]] && tail -n ${2:-20} $ZAP_HOME/history; return ;;
  esac

  local _zap_req="$*" _zap_code _zap_errf _zap_status=0 _zap_tries=0 _zap_prompt
  _zap_prompt=$(_zap_prompt "$_zap_req")

  while true; do
    _zap_code=$(_zap_think "$_zap_prompt") || return 1

    if [[ -z $_zap_code ]]; then
      print -u2 "  ${_r}$ZAP_PROVIDER didn't send anything back${_x}"
      return 1
    fi
    # the model answers with a comment when it can't or won't do it
    if [[ $_zap_code == '# '* && $_zap_code != *$'\n'* ]]; then
      print -r -- "  ${_y}${_zap_code#\# }${_x}"
      return 1
    fi

    _zap_show
    if [[ $ZAP_AUTORUN != 1 ]] || _zap_risky "$_zap_code"; then
      _zap_confirm || return 0
    fi

    _zap_errf=$(mktemp -t zap)
    print -s -- "$_zap_code"   # up-arrow gives you the real command next time
    eval "$_zap_code" 2> >(tee $_zap_errf >&2)
    _zap_status=$?
    sleep 0.05                 # let tee catch up
    _zap_log

    if (( _zap_status == 0 || _zap_status == 130 || _zap_tries >= 2 )); then
      rm -f $_zap_errf
      return $_zap_status
    fi

    print
    if ! read -q "?  ${_y}that failed (exit $_zap_status). ask $ZAP_PROVIDER for a fix? [y/N]${_x} " </dev/tty; then
      print; rm -f $_zap_errf; return $_zap_status
    fi
    print
    _zap_prompt=$(_zap_prompt "$_zap_req" "$_zap_code" $_zap_status "$(tail -n 30 $_zap_errf)")
    rm -f $_zap_errf
    (( _zap_tries++ ))
  done
}

_zap_help() {
  print -r -- "${_b}zap${_x} — say what you want, get the command.

  ${_y}/zap${_x} find every video over 1GB on my desktop
  ${_y}/zap${_x} convert the pngs in this folder to jpg
  ${_y}/zap${_x} what's using port 3000? kill it

  zap --use <claude|codex|gemini|ollama> [model]   switch AI
  zap --auto on|off                                 run safe commands without asking
  zap --history [n]                                 last runs
  zap --version

  Using ${_b}$ZAP_PROVIDER${_x}${ZAP_MODEL:+ ($ZAP_MODEL)}. Settings live in $ZAP_HOME/config"
}

_zap_use() {
  if [[ $1 != (claude|codex|gemini|ollama) ]]; then
    print -u2 "pick one of: claude codex gemini ollama"
    return 1
  fi
  if ! (( $+commands[$1] )); then
    print -u2 "  ${_r}$1 isn't installed (or not on your PATH)${_x}"
    return 1
  fi
  ZAP_PROVIDER=$1 ZAP_MODEL=${2:-}
  _zap_save
  print "  ${_g}✓${_x} zap now uses $1${2:+ ($2)}"
}

_zap_auto() {
  case $1 in
    on)  ZAP_AUTORUN=1 ;;
    off) ZAP_AUTORUN=0 ;;
    *)   [[ $ZAP_AUTORUN == 1 ]] && print "auto-run is on" || print "auto-run is off"
         print "use: zap --auto on|off"; return ;;
  esac
  _zap_save
  if [[ $1 == on ]]; then
    print "  ${_g}✓${_x} safe commands now run right away. risky ones still ask."
  else
    print "  ${_g}✓${_x} zap asks before running anything again"
  fi
}

_zap_save() {
  mkdir -p $ZAP_HOME
  print -r -- "ZAP_PROVIDER=$ZAP_PROVIDER"$'\n'"ZAP_MODEL=$ZAP_MODEL"$'\n'"ZAP_AUTORUN=${ZAP_AUTORUN:-0}" > $ZAP_HOME/config
}

_zap_prompt() {
  local req=$1 prev=$2 st=$3 err=$4 t
  local -a have
  for t in brew git python3 node ffmpeg jq magick yt-dlp docker rg fd; do
    (( $+commands[$t] )) && have+=$t
  done

  print -r -- "You turn plain requests into shell code for macOS. The code runs in zsh, in the user's current folder.

Rules:
- Reply with the code only. No explanation, no markdown, no backticks.
- One line whenever possible. Several lines only when it really needs a script.
- macOS ships BSD tools: use sed -i '', stat -f, date -v and so on.
- Extra tools you may use (they're installed): ${(j:, :)have:-none}.
- If you need Python, call python3 with a heredoc.
- No sudo unless the task can't work without it.
- If the request is unclear or impossible, reply with one line starting with \"# \" that says why.

macOS $(sw_vers -productVersion 2>/dev/null), $(uname -m)
Folder: $PWD
Files here: $(ls -1Ap 2>/dev/null | head -40 | tr '\n' ' ')

Request: $req"

  if [[ -n $prev ]]; then
    print -r -- "
Your last answer was:
$prev

It failed with exit code $st. Error output:
$err

Reply with fixed code only."
  fi
}

_zap_ask() {
  local -a m
  case $ZAP_PROVIDER in
    claude)
      [[ -n $ZAP_MODEL ]] && m=(--model $ZAP_MODEL)
      # skipping MCP servers, project settings and session files takes ~3s off each call
      claude -p "$1" $m --tools "" --strict-mcp-config --setting-sources user \
        --no-session-persistence --effort low </dev/null ;;
    codex)
      local o=$(mktemp -t zap)
      [[ -n $ZAP_MODEL ]] && m=(-m $ZAP_MODEL)
      codex exec --skip-git-repo-check -s read-only $m --output-last-message $o "$1" >/dev/null </dev/null
      local st=$?; cat $o; rm -f $o; return $st ;;
    gemini)
      [[ -n $ZAP_MODEL ]] && m=(-m $ZAP_MODEL)
      gemini $m -p "$1" </dev/null ;;
    ollama)
      ollama run ${ZAP_MODEL:-llama3.2} "$1" </dev/null ;;
    *)
      print -u2 "unknown AI '$ZAP_PROVIDER' in $ZAP_HOME/config"
      return 1 ;;
  esac
}

# ask the AI while Flash bounces, print the cleaned-up answer
_zap_think() {
  local out=$(mktemp -t zap) i=0 st pid drawn=0
  local -a seq=(idle zap1 zap2 idle zap1 zap2 blink idle zap1 zap2 wink wink)

  _zap_ask "$1" >$out 2>$out.err &
  pid=$!
  trap "kill $pid 2>/dev/null; (( drawn )) && print -nu2 '\e[${_zap_flash_h}A\e[J'; print -nu2 '\e[?25h'; rm -f $out $out.err; return 130" INT

  if [[ -t 2 ]]; then
    _zap_flash_load
    print -nu2 '\e[?25l'
    while kill -0 $pid 2>/dev/null; do
      (( drawn )) && print -nu2 "\e[${_zap_flash_h}A"
      print -rnu2 -- "${_zap_flash[${seq[i % $#seq + 1]}]}"
      drawn=1
      (( i++ ))
      sleep 0.09
    done
    print -nu2 "\e[${_zap_flash_h}A\e[J\e[?25h"
  fi
  wait $pid; st=$?

  if (( st != 0 )); then
    print -u2 "  ${_r}$ZAP_PROVIDER failed:${_x}"
    cat $out $out.err | tail -n 5 | sed 's/^/  /' >&2
    rm -f $out $out.err
    return 1
  fi

  local s=$(<$out)
  rm -f $out $out.err
  s=${s//$'\e'\[[0-9;?]#[a-zA-Z]/}       # terminal colors
  s=${s//<think>*<\/think>/}             # reasoning models
  local -a lines=("${(@f)s}")
  lines=(${lines:#\`\`\`*})              # markdown fences
  s=${(F)lines}
  s=${s##[[:space:]]#}
  s=${s%%[[:space:]]#}
  [[ $s != *$'\n'* ]] && s=${s#\$ }
  print -r -- "$s"
}

# Flash, the little spark that keeps you company while the AI thinks.
# One character per pixel; drawn with half blocks so two pixels fit in one row.
typeset -gA _zap_flash
typeset -g _zap_flash_h=9

_zap_flash_load() {
  (( $#_zap_flash )) && return
  local -A pal=( Y 220 O 208 W 230 K 235 S 229 )
  local -a idle=(
    "..........OOOOO."
    ".........OYYYWO."
    "........OYYYWO.."
    ".......OYYYYO..."
    "......OYYYYO...."
    "...OOOYYYYYOOOO."
    "..OYKKKYYYKKKYO."
    "..OYYYYYYYYYYYO."
    "..OYYWKYYYYWKYO."
    "..OYYKKYYYYKKYO."
    "..OYYYYYYYYKYYO."
    "..OYYYYKKKKYYO.."
    "..OOOOYYYYYOO..."
    ".....OYYYYO....."
    "....OYYYO......."
    "...OYYO........."
    "..OYO..........."
    "..OO............"
  )
  local -a blink=("${idle[@]}") wink=("${idle[@]}") zap1=("${idle[@]}") zap2=("${idle[@]}")
  blink[9]="..OYYYYYYYYYYYO."
  wink[9]="..OYYYYYYYYWKYO."
  zap1[4]="S......OYYYYO..."
  zap1[8]="..OYYYYYYYYYYYOS"
  zap1[14]=".....OYYYYO...S."
  zap2[3]=".S......OYYYWO.."
  zap2[11]="S.OYYYYYYYYKYYO."
  zap2[16]="...OYYO......S.."

  local name y x t b line out
  for name in idle blink wink zap1 zap2; do
    local -a rows=("${(@P)name}")
    out=
    for (( y = 1; y <= $#rows; y += 2 )); do
      line="  "
      for (( x = 1; x <= 16; x++ )); do
        t=${rows[y][x]} b=${rows[y+1][x]}
        if [[ $t == . && $b == . ]]; then line+=$'\e[0m '
        elif [[ $b == . ]]; then line+=$'\e[0;38;5;'$pal[$t]'m▀'
        elif [[ $t == . ]]; then line+=$'\e[0;38;5;'$pal[$b]'m▄'
        else line+=$'\e[38;5;'$pal[$t]';48;5;'$pal[$b]'m▀'
        fi
      done
      out+=$line$'\e[0m\e[K\n'
    done
    _zap_flash[$name]=$out
  done
}

_zap_flash_show() {
  [[ -t 1 ]] || return
  _zap_flash_load
  print -rn -- "${_zap_flash[$1]}"
}

_zap_risky() {
  local re='(^|[^[:alnum:]_-])(sudo|rm|dd|shred|srm|mkfs[.a-z]*|killall|pkill|launchctl|csrutil|nvram|diskutil[[:space:]]+(erase[a-zA-Z]*|partition[a-zA-Z]*|zero[a-zA-Z]*|secureErase|reformat)|chmod[[:space:]]+-R|chown[[:space:]]+-R|defaults[[:space:]]+delete|git[[:space:]]+(reset[[:space:]]+--hard|clean|push.*(-f|--force)))([[:space:]]|$)|-delete([[:space:]]|$)|>[[:space:]]*/dev/r?disk|(curl|wget)[^|]*[|][[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh'
  [[ $1 =~ $re ]]
}

_zap_show() {
  local c=$_y l
  _zap_risky "$_zap_code" && c=$_r
  print
  if [[ $_zap_code == *$'\n'* ]]; then
    print -r -- "  ${_d}┌──${_x}"
    for l in "${(@f)_zap_code}"; do
      print -r -- "  ${_d}│${_x} ${c}$l${_x}"
    done
    print -r -- "  ${_d}└──${_x}"
  else
    print -r -- "  ${c}⚡${_x} ${_b}$_zap_code${_x}"
  fi
  print
}

_zap_confirm() {
  local ans
  if _zap_risky "$_zap_code"; then
    print -r -- "  ${_r}${_b}careful:${_x}${_r} this can delete or change things you can't get back.${_x}"
    read -r "ans?  type ${_b}yes${_x} to run it, ${_b}e${_x} to edit, anything else cancels: " </dev/tty
    case $ans in
      yes) return 0 ;;
      e|E) _zap_edit && _zap_show && _zap_confirm; return ;;
    esac
  else
    read -k1 "ans?  run it? ${_d}[y/N/e]${_x} " </dev/tty
    print
    case $ans in
      y|Y) return 0 ;;
      e|E) _zap_edit && _zap_show && _zap_confirm; return ;;
    esac
  fi
  print "  ${_d}ok, nothing ran${_x}"
  return 1
}

_zap_edit() {
  if [[ $_zap_code == *$'\n'* ]]; then
    local f=$(mktemp -t zap).sh
    print -r -- "$_zap_code" > $f
    ${=EDITOR:-nano} $f </dev/tty
    _zap_code=$(<$f)
    rm -f $f
  else
    vared -p "  edit: " _zap_code
  fi
  [[ -n $_zap_code ]]
}

_zap_log() {
  mkdir -p $ZAP_HOME
  print -r -- "$(date '+%F %T')"$'\t'"$ZAP_PROVIDER"$'\t'"$_zap_req"$'\t'"${_zap_code//$'\n'/; }"$'\t'"$_zap_status" >> $ZAP_HOME/history
}

# Make `/zap ...` work at the prompt. Without this zsh would look for a file
# called /zap, and words like "what's" or "?" would trip up the parser.
_zap_accept_line() {
  setopt local_options extended_glob
  if [[ $BUFFER == (/zap|zap)(| *) ]]; then
    local rest=${BUFFER#/}
    rest=${rest#zap}
    rest=${rest## #}
    if [[ -n $rest ]]; then
      BUFFER="zap ${(q-)rest}"
    else
      BUFFER=zap
    fi
  fi
  zle _zap_orig_accept_line
}

if [[ -o interactive && -o zle && -z $_ZAP_HOOKED ]]; then
  _ZAP_HOOKED=1
  zle -A accept-line _zap_orig_accept_line
  zle -N accept-line _zap_accept_line
fi
