# agent-skills

Kendi skill repolarımı tüm makinelerde (Claude, Codex, OpenCode…) kurulu ve güncel tutar.

- **Skill eklemek / çıkarmak:** `skills.txt`'e satır ekle ya da sil, push et.
- **Skill güncellemek:** skill'in kendi reposuna push et.
- Her makine saatte bir `sync.sh` çalıştırır (macOS: launchd, Linux: cron); değişiklik en geç bir saat içinde gelir. Acilse makinede `~/.agents/agent-skills/sync.sh`'i elle çalıştır. Claude yeni oturumda görür.

## Skill eklemek: `skill-ekle`
Herhangi bir makinede Claude, Codex ya da Antigravity'ye "bu skill'i ekle: <GitHub linki>" de. `skill-ekle` skill'i repodaki skill'leri listeler, gerekirse hangisini istediğini sorar, manifest'e ekleyip push eder ve sync'i hemen çalıştırır. Diğer makineler en geç bir saatte alır. "şu skill'i kaldır" da çalışır.

Elle: `~/.agents/agent-skills/skill-add.sh list | list-skills <kaynak> | add <kaynak> [ad=klasör …] | remove <ad>`

## Bir makineyi bağlamak
```bash
curl -fsSL https://raw.githubusercontent.com/buraksu42/agent-skills/main/install.sh | bash
```

## Düzen
- Klonlar: `~/.agents/skill-repos/<owner>/<repo>`
- Kaynak: `~/.agents/skills/<ad>` (Codex ve OpenCode buradan okur)
- Aynalar: `~/.claude/skills/<ad>` (Claude Code), `~/.gemini/config/skills/<ad>` (Antigravity IDE), `~/.gemini/antigravity-cli/skills/<ad>` (Antigravity CLI; `~/.gemini` varsa)
- `~/.agents/skills`'e başka yoldan kurulan skill'ler (npx skills, elle) de Claude ve Antigravity'ye aynalanır. Hedefte aynı adla bir şey varsa dokunulmaz.
- Önceden var olan düz kopyalar silinmez, `~/.agents/skills-backup/` altına taşınır.
- Log: `~/.agents/skills-sync.log` — elle çalıştırma: `~/.agents/agent-skills/sync.sh`
- Private repolar (`git@github.com:…`) için makinenin GitHub SSH erişimi olmalı; yoksa o skill atlanır, diğerleri çalışır.
