#!/usr/bin/env bash
# skills.txt'teki skill repolarını klonlar/günceller ve tüm araçlara bağlar:
#   ~/.agents/skills/<ad>               -> ~/.agents/skill-repos/<owner>/<repo>[/klasör]   (Codex, OpenCode)
#   ~/.claude/skills/<ad>               -> ~/.agents/skills/<ad>                           (Claude Code)
#   ~/.gemini/config/skills/<ad>        -> ~/.agents/skills/<ad>                           (Antigravity IDE)
#   ~/.gemini/antigravity-cli/skills/<ad> -> ~/.agents/skills/<ad>                         (Antigravity CLI)
# Ayrıca ~/.agents/skills'te olup manifest dışından gelen skill'ler de (npx skills, elle kurulanlar)
# Claude ve Antigravity'ye aynalanır. macOS (bash 3.2) ve Linux uyumlu. Tekrar çalıştırmak güvenli.
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

# Aynalanacak klasörler: Claude her zaman, Antigravity yalnızca kuruluysa (~/.gemini varsa)
MIRRORS="$CLAUDE"
if [ -d "$HOME/.gemini" ]; then
  MIRRORS="$MIRRORS
$HOME/.gemini/config/skills
$HOME/.gemini/antigravity-cli/skills"
fi

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

# 2) Her skill'i klonla/güncelle ve ~/.agents/skills'e bağla
managed=""; pulled=""; failed=""
while read -r src name sub _rest <&3; do
  case "$src" in ''|\#*) continue ;; esac
  case "$src" in *://*|git@*) url="$src" ;; *) url="https://github.com/$src.git" ;; esac
  key="${src%.git}"; key="${key#*://}"; key="${key#*@}"
  case "$src" in *://*|git@*) key="${key#*[:/]}" ;; esac      # -> owner/repo
  repo="${key##*/}"
  name="${name:-$repo}"
  dir="$REPOS/$key"

  # Eski düzenden taşı: skill-repos/<repo> -> skill-repos/<owner>/<repo>
  if [ ! -e "$dir" ] && [ -d "$REPOS/$repo/.git" ] && [ "$REPOS/$repo" != "$dir" ] \
     && git -C "$REPOS/$repo" remote get-url origin 2>/dev/null | grep -qi "$key"; then
    mkdir -p "$(dirname "$dir")" && mv "$REPOS/$repo" "$dir"
  fi

  if printf '%s' "$failed" | grep -qx "$key"; then continue; fi
  if ! printf '%s' "$pulled" | grep -qx "$key"; then
    if [ -d "$dir/.git" ]; then
      before=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
      if git -C "$dir" pull -q --ff-only </dev/null; then
        after=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
        if [ "$before" != "$after" ]; then
          log "GÜNCEL   $key -> $(git -C "$dir" log -1 --format='%h %s' | cut -c1-70)"; changes=$((changes+1))
        fi
      else
        log "HATA     $key: git pull başarısız (erişim ya da bu makinede yerel değişiklik)"; err=1
      fi
    elif [ -e "$dir" ]; then
      log "HATA     $key: $dir git klonu değil, dokunmadım"; err=1
      failed="$failed$key
"; continue
    else
      mkdir -p "$(dirname "$dir")"
      if git clone -q "$url" "$dir" </dev/null 2>/dev/null; then
        log "KLON     $key ($url)"; changes=$((changes+1))
      else
        rm -rf "$dir"
        log "HATA     $key: klonlanamadı ($url) — private repoysa bu makinenin GitHub erişimi yok"; err=1
        failed="$failed$key
"; continue
      fi
    fi
    pulled="$pulled$key
"
  fi

  skilldir="$dir${sub:+/$sub}"
  if [ ! -f "$skilldir/SKILL.md" ]; then
    found=$(cd "$dir" && find . -maxdepth 4 -name SKILL.md -not -path './.git/*' | head -5 | tr '\n' ' ')
    log "HATA     $name: SKILL.md yok ($skilldir). Repoda bulunanlar: ${found:-hiç} -> skills.txt'e klasörü ekle"; err=1; continue
  fi

  link "$AGENTS/$name" "../skill-repos/$key${sub:+/$sub}" agents
  managed="$managed$name
"
  count=$((count+1))
done 3< "$MANIFEST"

# 3) Manifest'ten çıkarılan skill'leri ~/.agents/skills'ten kaldır (yalnızca bu scriptin kurduğu linkler)
if [ -f "$STATE" ]; then
  while read -r old; do
    [ -z "$old" ] && continue
    printf '%s' "$managed" | grep -qx "$old" && continue
    if [ -L "$AGENTS/$old" ] && readlink "$AGENTS/$old" | grep -q '^\.\./skill-repos/'; then
      rm -f "$AGENTS/$old"; log "KALDIRILDI $AGENTS/$old"; changes=$((changes+1))
    fi
  done < "$STATE"
fi
printf '%s' "$managed" > "$STATE"

# 4) ~/.agents/skills'teki her skill'i Claude ve Antigravity'ye aynala.
#    Hedefte aynı adla bir şey varsa (senin kurulumun) dokunulmaz; kaynağı silinmiş linkler temizlenir.
total=0
for s in "$AGENTS"/*; do [ -f "$s/SKILL.md" ] && total=$((total+1)); done
printf '%s\n' "$MIRRORS" | while read -r m; do
  [ -z "$m" ] && continue
  mkdir -p "$m"
  added=0; removed=0
  for t in "$m"/* "$m"/.[!.]*; do
    [ -L "$t" ] || continue
    [ -e "$t" ] && continue
    case "$(readlink "$t")" in
      "$AGENTS"/*|*/.agents/skills/*|../../.agents/skills/*) rm -f "$t"; removed=$((removed+1)) ;;
    esac
  done
  for s in "$AGENTS"/*; do
    n=$(basename "$s")
    [ -f "$s/SKILL.md" ] || continue
    if [ -e "$m/$n" ] || [ -L "$m/$n" ]; then continue; fi
    ln -s "$AGENTS/$n" "$m/$n" && added=$((added+1))
  done
  if [ $added -gt 0 ] || [ $removed -gt 0 ]; then
    log "AYNA     $m: $added eklendi, $removed kaldırıldı"
    touch "$LOCK/changed"
  fi
done
[ -f "$LOCK/changed" ] && changes=$((changes+1))

if [ -t 1 ] || [ "$changes" -gt 0 ] || [ "$err" -ne 0 ]; then
  log "ÖZET     $(hostname -s 2>/dev/null || hostname): manifest'ten $count skill, ~/.agents/skills'te toplam $total skill, $changes değişiklik, $([ $err -eq 0 ] && echo hata yok || echo 'HATA VAR')"
fi
exit $err
