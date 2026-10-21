#!/usr/bin/env bash
# Bir makineyi skill senkronuna bağlar: manifest reposunu klonlar, ilk sync'i çalıştırır,
# saatte bir otomatik sync kurar (macOS: launchd, Linux: cron). Tekrar çalıştırmak güvenli.
set -euo pipefail

REPO_URL="${AGENT_SKILLS_REPO:-https://github.com/buraksu42/agent-skills.git}"
ROOT="${AGENT_SKILLS_ROOT:-$HOME/.agents}"
META="$ROOT/agent-skills"
SYNC="$META/sync.sh"
LOG="$ROOT/skills-sync.log"
LABEL="com.buraksu42.agent-skills-sync"

command -v git >/dev/null || { echo "git yok, önce git kur."; exit 1; }
mkdir -p "$ROOT"
if [ -d "$META/.git" ]; then git -C "$META" pull -q --ff-only; else git clone -q "$REPO_URL" "$META"; fi
chmod +x "$SYNC"

schedule="atlandı"
if [ -z "${AGENT_SKILLS_NO_SCHEDULE:-}" ]; then
  case "$(uname -s)" in
    Darwin)
      plist="$HOME/Library/LaunchAgents/$LABEL.plist"
      mkdir -p "$(dirname "$plist")"
      cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>-c</string>
    <string>"$SYNC" &gt;&gt; "$LOG" 2&gt;&amp;1</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
      uid=$(id -u)
      launchctl bootout "gui/$uid/$LABEL" 2>/dev/null || launchctl bootout "user/$uid/$LABEL" 2>/dev/null || true
      if launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null || launchctl bootstrap "user/$uid" "$plist" 2>/dev/null; then
        schedule="launchd, saatte bir (uykudan uyanınca da çalışır)"
      else
        schedule="KURULAMADI — Mac'te oturum açıkken tekrar çalıştır"
      fi
      ;;
    Linux)
      if command -v crontab >/dev/null; then
        line="17 * * * * \"$SYNC\" >> \"$LOG\" 2>&1 # agent-skills-sync"
        { crontab -l 2>/dev/null | grep -v 'agent-skills-sync' || true; echo "$line"; } | crontab -
        schedule="cron, saatte bir"
      else
        schedule="KURULAMADI — crontab yok"
      fi
      ;;
  esac
fi

echo "== İlk sync =="
"$SYNC" || true
echo "== Zamanlayıcı: $schedule"
echo "== Log: $LOG   Elle çalıştırmak için: $SYNC"
