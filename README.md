# agent-skills

Kendi skill repolarımı tüm makinelerde (Claude, Codex, OpenCode…) kurulu ve güncel tutar.

- **Skill eklemek / çıkarmak:** `skills.txt`'e satır ekle ya da sil, push et.
- **Skill güncellemek:** skill'in kendi reposuna push et.
- Her makine saatte bir `sync.sh` çalıştırır (macOS: launchd, Linux: cron); değişiklik en geç bir saat içinde gelir. Acilse makinede `~/.agents/agent-skills/sync.sh`'i elle çalıştır. Claude yeni oturumda görür.

## Bir makineyi bağlamak
```bash
curl -fsSL https://raw.githubusercontent.com/buraksu42/agent-skills/main/install.sh | bash
```

## Düzen
- Klonlar: `~/.agents/skill-repos/<repo>`
- Linkler: `~/.agents/skills/<ad>` ve `~/.claude/skills/<ad>`
- Önceden var olan düz kopyalar silinmez, `~/.agents/skills-backup/` altına taşınır.
- Log: `~/.agents/skills-sync.log` — elle çalıştırma: `~/.agents/agent-skills/sync.sh`
- Private repolar (`git@github.com:…`) için makinenin GitHub SSH erişimi olmalı; yoksa o skill atlanır, diğerleri çalışır.
