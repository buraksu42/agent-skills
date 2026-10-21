#!/usr/bin/env bash
# agent-skills manifest'ini yönetir (skill-ekle skill'i bunu çağırır).
#   skill-add.sh list-skills <kaynak>                 Repodaki SKILL.md'leri listeler (ad <TAB> klasör)
#   skill-add.sh add <kaynak> [ad=klasör ...]         Manifest'e ekler, push eder, sync'i çalıştırır
#   skill-add.sh remove <ad> [ad ...]                 Manifest'ten çıkarır, push eder, sync'i çalıştırır
#   skill-add.sh list                                 Manifest'teki skill'leri listeler
# <kaynak>: owner/repo | https://github.com/owner/repo[.git] | https://github.com/owner/repo/tree/<dal>/<klasör>
#           | git@github.com:owner/repo.git (private repolar)
# Bir GitHub "tree" linki verilirse ve ad=klasör yazılmazsa, o klasördeki skill eklenir.
set -uo pipefail

ROOT="${AGENT_SKILLS_ROOT:-$HOME/.agents}"
META="$ROOT/agent-skills"
MANIFEST="$META/skills.txt"
SYNC="$META/sync.sh"
LOCK="$ROOT/.skills-sync.lock"
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=15}"

die() { echo "HATA: $*" >&2; exit 1; }
[ -f "$MANIFEST" ] || die "$MANIFEST yok. Önce kur: curl -fsSL https://raw.githubusercontent.com/buraksu42/agent-skills/main/install.sh | bash"

TREE_SUB=""
# parse <kaynak> -> SRC (manifest'e yazılacak biçim), URL (clone), TREE_SUB
parse() {
  local s="$1" p
  s="${s%/}"
  case "$s" in
    git@*)            SRC="$s"; URL="$s" ;;
    http*://github.com/*/*/tree/*|github.com/*/*/tree/*)
      p="${s#*github.com/}"                       # owner/repo/tree/branch/path
      SRC="$(echo "$p" | cut -d/ -f1-2)"
      TREE_SUB="$(echo "$p" | cut -d/ -f5-)"
      URL="https://github.com/$SRC.git" ;;
    http*://github.com/*|github.com/*)
      p="${s#*github.com/}"; p="${p%.git}"
      SRC="$(echo "$p" | cut -d/ -f1-2)"; URL="https://github.com/$SRC.git" ;;
    *://*)            SRC="$s"; URL="$s" ;;
    */*)              SRC="${s%.git}"; URL="https://github.com/$SRC.git" ;;
    *)                die "kaynak anlaşılamadı: $1 (owner/repo ya da GitHub linki ver)" ;;
  esac
}

TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; [ "${LOCKED:-0}" = 1 ] && rm -rf "$LOCK"; }
trap cleanup EXIT

fetch() {  # repoyu geçici klasöre sığ klonla
  TMP=$(mktemp -d)
  git clone -q --depth 1 "$URL" "$TMP/r" </dev/null 2>/dev/null \
    || die "klonlanamadı: $URL (private ise git@github.com:owner/repo.git biçimini kullan ve bu makinenin GitHub SSH erişimini kontrol et)"
}

skill_name() {  # SKILL.md frontmatter'ındaki ad
  grep -m1 '^name:' "$1" 2>/dev/null | sed 's/^name:[[:space:]]*//; s/["'\'']//g; s/[[:space:]]*$//'
}

list_skills() {
  (cd "$TMP/r" && find . -name SKILL.md -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/tests/*' -not -path '*/test/*' 2>/dev/null) \
  | sed 's#^\./##; s#/\{0,1\}SKILL.md$##' \
  | awk '{ d=$0; dot=(d ~ /(^|\/)\./) ? 1 : 0; print dot "\t" d }' | sort -k1,1n -k2,2 | cut -f2 \
  | while read -r d; do
      n=$(skill_name "$TMP/r/${d:+$d/}SKILL.md"); [ -z "$n" ] && n=$(basename "${d:-$(basename "$SRC")}")
      printf '%s\t%s\n' "$n" "${d:-.}"
    done
}

lock() {  # sync ile çakışmasın
  local i=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    i=$((i+1)); [ $i -gt 60 ] && die "sync kilidi 2 dk'dır açılmadı ($LOCK)"; sleep 2
  done
  LOCKED=1
}

commit_push() {  # $1 = mesaj
  git -C "$META" add skills.txt
  git -C "$META" -c user.name="${GIT_AUTHOR_NAME:-skill-ekle}" -c user.email="${GIT_AUTHOR_EMAIL:-skill-ekle@$(hostname -s 2>/dev/null || hostname)}" \
      commit -qm "$1" || die "commit başarısız"
  local tries=0
  until git -C "$META" push -q origin HEAD:main </dev/null 2>/dev/null \
        || git -C "$META" push -q git@github.com:buraksu42/agent-skills.git HEAD:main </dev/null 2>/dev/null; do
    tries=$((tries+1))
    if [ $tries -ge 2 ]; then
      git -C "$META" reset -q --soft HEAD~1; git -C "$META" checkout -q -- skills.txt
      die "push başarısız, değişiklik geri alındı. Bu makinenin GitHub'a yazma erişimi yok (gh auth setup-git ya da GitHub SSH anahtarı gerekli)."
    fi
    git -C "$META" pull -q --rebase origin main </dev/null || die "rebase başarısız"
  done
}

prep() {  # kilit + temiz ve güncel manifest
  lock
  if [ -n "$(git -C "$META" status --porcelain skills.txt)" ]; then
    die "skills.txt'te push edilmemiş yerel değişiklik var: $META — önce onu commit/push et ya da geri al."
  fi
  git -C "$META" pull -q --ff-only </dev/null || die "manifest güncellenemedi (git pull)"
}

managed_names() {
  awk '!/^[[:space:]]*(#|$)/ { if ($2 != "") print $2; else { r=$1; sub(/\.git$/,"",r); n=split(r,a,/[\/:]/); print a[n] } }' "$MANIFEST"
}

run_sync() {
  rm -rf "$LOCK"; LOCKED=0
  echo "== sync çalışıyor…"
  "$SYNC" | grep -E "KLON|BAĞLANDI|KALDIRILDI|AYNA|HATA|ÖZET" || true
}

cmd="${1:-}"; shift || true
case "$cmd" in
  list)
    managed_names | sort ;;

  list-skills)
    [ $# -ge 1 ] || die "kullanım: list-skills <kaynak>"
    parse "$1"; fetch
    echo "# kaynak: $SRC${TREE_SUB:+  (link klasörü: $TREE_SUB)}"
    list_skills ;;

  add)
    [ $# -ge 1 ] || die "kullanım: add <kaynak> [ad=klasör ...]"
    parse "$1"; shift; fetch
    pairs="$*"
    if [ -z "$pairs" ]; then
      if [ -n "$TREE_SUB" ]; then d="$TREE_SUB"
      elif [ -f "$TMP/r/SKILL.md" ]; then d=""
      else
        echo "Repo kökünde SKILL.md yok. Hangi skill(ler)? Bulunanlar:" >&2; list_skills >&2; exit 2
      fi
      n=$(skill_name "$TMP/r/${d:+$d/}SKILL.md"); [ -z "$n" ] && n=$(basename "${d:-${SRC%.git}}")
      pairs="$n=$d"
    fi
    # doğrula
    lines=""; names=""
    for pr in $pairs; do
      n="${pr%%=*}"; d="${pr#*=}"; [ "$d" = "." ] && d=""
      case "$n" in ''|*[!A-Za-z0-9._-]*) die "geçersiz skill adı: '$n'" ;; esac
      [ -f "$TMP/r/${d:+$d/}SKILL.md" ] || die "$SRC içinde ${d:-kök}/SKILL.md yok"
      lines="$lines$SRC  $n${d:+  $d}
"; names="$names $n"
    done
    prep
    for n in $names; do
      managed_names | grep -qx "$n" && die "'$n' zaten manifest'te. Farklı bir ad ver: ad=klasör"
      if [ -e "$ROOT/skills/$n" ] && ! readlink "$ROOT/skills/$n" 2>/dev/null | grep -q '^\.\./skill-repos/'; then
        echo "UYARI: ~/.agents/skills/$n bu makinede elle kurulmuş; sync onu ~/.agents/skills-backup/ altına taşıyıp git sürümüyle değiştirecek."
      fi
    done
    printf '%s' "$lines" >> "$MANIFEST"
    commit_push "skill ekle:$names"
    echo "== manifest'e eklendi ve push edildi:"; printf '%s' "$lines" | sed 's/^/   /'
    run_sync ;;

  remove)
    [ $# -ge 1 ] || die "kullanım: remove <ad> [ad ...]"
    prep
    for n in "$@"; do managed_names | grep -qx "$n" || die "'$n' manifest'te yok"; done
    tmpf=$(mktemp)
    awk -v names=" $* " '
      /^[[:space:]]*(#|$)/ { print; next }
      { n=$2; if (n=="") { r=$1; sub(/\.git$/,"",r); k=split(r,a,/[\/:]/); n=a[k] }
        if (index(names, " " n " ")) next; print }' "$MANIFEST" > "$tmpf" && mv "$tmpf" "$MANIFEST"
    commit_push "skill kaldır: $*"
    echo "== manifest'ten çıkarıldı ve push edildi: $*"
    run_sync ;;

  *)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
