#!/usr/bin/env bash
# skills.txt'teki skill repolarını klonlar/günceller ve
#   ~/.agents/skills/<ad>  ->  ~/.agents/skill-repos/<repo>[/klasör]
#   ~/.claude/skills/<ad>  ->  ../../.agents/skills/<ad>
# olarak bağlar. Claude ~/.claude/skills'i, Codex/OpenCode vb. ~/.agents/skills'i okur.
# macOS (bash 3.2) ve Linux uyumlu. Tekrar tekrar çalıştırmak güvenli.
set -uo pipefail

ROOT="${AGENT_SKILLS_ROOT:-$HOME/.agents}"
META="$ROOT/agent-skills"
REPOS="$ROOT/skill-repos"
AGENTS="$ROOT/skills"
CLAUDE="$HOME/.claude/skills"
BACKUP="$ROOT/skills-backup"
LOG="$ROOT/skills-sync.log"
LOCK="$ROOT/.skills-sync.lock"
STATE="$REPOS/.managed"
MANIFEST="$META/skills.txt"
export GIT_TERMINAL_PROMPT=0          # zamanlanmış çalışmada şifre sorup takılmasın
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=15}"

mkdir -p "$REPOS" "$AGENTS" "$CLAUDE"

# Log çok büyümesin
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt 5000 ]; then
  tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# Aynı anda iki sync çalışmasın (macOS'ta flock yok, mkdir kilidi)
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0
  else
    echo "Başka bir sync çalışıyor, çıkıyorum."; exit 0
  fi
fi
trap 'rm -rf "$LOCK"' EXIT

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) $*"; }
err=0; changes=0; count=0

realdir() { (cd -P "$1" 2>/dev/null && pwd); }

# link <yol> <hedef (yol'un klasörüne göre)> <yedek etiketi>
link() {
  local path="$1" target="$2" tag="$3" want got
  want=$(cd "$(dirname "$path")" && realdir "$target")
  if [ -L "$path" ]; then
    got=$(realdir "$path")
    [ -n "$want" ] && [ "$got" = "$want" ] && return 0
    rm -f "$path"
  elif [ -e "$path" ]; then
    mkdir -p "$BACKUP"
    mv "$path" "$BACKUP/$tag-$(basename "$path")-$(date +%Y%m%d%H%M%S)"
    log "YEDEK    $path -> $BACKUP/"
  fi
  ln -s "$target" "$path" && { log "BAĞLANDI $path"; changes=$((changes+1)); }
}

# 1) Manifest reposunun kendisini güncelle
if [ -d "$META/.git" ]; then
  git -C "$META" pull -q --ff-only </dev/null || { log "HATA     manifest reposu güncellenemedi, yerel kopyayla devam"; err=1; }
fi
[ -f "$MANIFEST" ] || { log "HATA     $MANIFEST yok"; exit 1; }

# 2) Her skill'i klonla/güncelle ve bağla
managed=""
while read -r src name sub _rest <&3; do
  case "$src" in ''|\#*) continue ;; esac
  case "$src" in *://*|git@*) url="$src" ;; *) url="https://github.com/$src.git" ;; esac
  repo=$(basename "${src##*:}" .git)
  name="${name:-$repo}"
  dir="$REPOS/$repo"

  if [ -d "$dir/.git" ]; then
    before=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
    if git -C "$dir" pull -q --ff-only </dev/null; then
      after=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
      if [ "$before" != "$after" ]; then
        log "GÜNCEL   $name -> $(git -C "$dir" log -1 --format='%h %s' | cut -c1-70)"; changes=$((changes+1))
      fi
    else
      log "HATA     $name: git pull başarısız (erişim ya da bu makinede yerel değişiklik)"; err=1
    fi
  elif [ -e "$dir" ]; then
    log "HATA     $name: $dir git klonu değil, dokunmadım"; err=1; continue
  else
    if git clone -q "$url" "$dir" </dev/null 2>/dev/null; then
      log "KLON     $name ($url)"; changes=$((changes+1))
    else
      rm -rf "$dir"
      log "HATA     $name: klonlanamadı ($url) — private repoysa bu makinenin GitHub erişimi yok"; err=1; continue
    fi
  fi

  skilldir="$dir${sub:+/$sub}"
  if [ ! -f "$skilldir/SKILL.md" ]; then
    found=$(cd "$dir" && find . -maxdepth 4 -name SKILL.md -not -path './.git/*' | head -5 | tr '\n' ' ')
    log "HATA     $name: SKILL.md yok ($skilldir). Repoda bulunanlar: ${found:-hiç} -> skills.txt'e klasörü ekle"; err=1; continue
  fi

  link "$AGENTS/$name" "../skill-repos/$repo${sub:+/$sub}" agents
  link "$CLAUDE/$name" "../../.agents/skills/$name" claude
  managed="$managed$name
"
  count=$((count+1))
done 3< "$MANIFEST"

# 3) Manifest'ten çıkarılan skill'leri kaldır (yalnızca bu scriptin kurduğu linkler)
if [ -f "$STATE" ]; then
  while read -r old; do
    [ -z "$old" ] && continue
    printf '%s' "$managed" | grep -qx "$old" && continue
    if [ -L "$AGENTS/$old" ] && readlink "$AGENTS/$old" | grep -q '^\.\./skill-repos/'; then
      rm -f "$AGENTS/$old"; log "KALDIRILDI $AGENTS/$old"; changes=$((changes+1))
    fi
    if [ -L "$CLAUDE/$old" ] && [ "$(readlink "$CLAUDE/$old")" = "../../.agents/skills/$old" ]; then
      rm -f "$CLAUDE/$old"; log "KALDIRILDI $CLAUDE/$old"
    fi
  done < "$STATE"
fi
printf '%s' "$managed" > "$STATE"

if [ -t 1 ] || [ "$changes" -gt 0 ] || [ "$err" -ne 0 ]; then
  log "ÖZET     $(hostname -s 2>/dev/null || hostname): $count skill aktif, $changes değişiklik, $([ $err -eq 0 ] && echo hata yok || echo 'HATA VAR')"
fi
exit $err
