---
name: skill-ekle
description: Adds, removes or lists skills that are kept in sync on all of Burak's machines (Mac mini, devbox, MacBook) and tools (Claude Code, Codex, OpenCode, Antigravity) through the agent-skills manifest. Use when the user says "bu skill'i ekle", "şu skill'i kur/yükle", "skill ekle", "skill'i kaldır/sil", "senkrondaki skill'ler neler", "add/install/remove this skill", or pastes a GitHub link, skills.sh link or `npx skills add …` command and wants it installed. Do not use for writing a new skill from scratch.
---

# skill-ekle

Skill'ler tek bir manifest'ten (`~/.agents/agent-skills/skills.txt`, GitHub: `buraksu42/agent-skills`) yönetilir. Manifest'e eklenen skill her makinede en geç bir saat içinde kurulur ve Claude Code, Codex, OpenCode ve Antigravity'ye bağlanır. Mekanik işi `~/.agents/agent-skills/skill-add.sh` yapar; `skills.txt`'i elle düzenleme.

Script yoksa bu makine senkrona bağlı değildir. Kullanıcıya şunu çalıştırmasını söyle ve dur:
`curl -fsSL https://raw.githubusercontent.com/buraksu42/agent-skills/main/install.sh | bash`

## Ekleme

1. **Kaynağı çıkar.** Kabul edilen biçimler: `owner/repo`, `https://github.com/owner/repo`, `https://github.com/owner/repo/tree/<dal>/<klasör>`, private repolar için `git@github.com:owner/repo.git`. `npx skills add owner/repo --skill x` komutunda repo `owner/repo`, skill `x`'tir. skills.sh linkinde sayfadaki GitHub reposunu kullan. Kaynak belli değilse kısaca sor.
2. **Repodaki skill'leri listele:**
   `~/.agents/agent-skills/skill-add.sh list-skills <kaynak>`
   Çıktı `ad<TAB>klasör` satırlarıdır. Nokta ile başlayan klasörlerdeki (`.cursor/`, `.kiro/`…) kopyalar başka araçlar için tekrarlardır. Aynı skill birden çok yerde varsa `.agents/skills/`, `skills/` ya da kök klasördekini seç.
3. **Hangisi eklenecek?**
   - Tek skill varsa, ya da kullanıcı birini adıyla söylediyse onu ekle.
   - Birden çok skill varsa ve kullanıcı belirtmediyse listeyi göster ve hangilerini istediğini sor (çoklu seçim). Repo büyükse hepsini kendiliğinden ekleme.
4. **Hızlı güvenlik bakışı:** Seçilen skill'in `SKILL.md` dosyasına ve varsa scriptlerine göz at. Kimlik bilgisi okuyan, dışarı veri gönderen ya da `curl | bash` çalıştıran bir şey görürsen eklemeden önce kullanıcıya söyle. Skill tüm makinelerde çalışacak.
5. **Ekle:**
   `~/.agents/agent-skills/skill-add.sh add <kaynak> <ad>=<klasör> [<ad>=<klasör> …]`
   Kökteki tek skill için `ad=klasör` gerekmez. Ad zaten varsa script reddeder; o durumda farklı bir ad öner.
6. **Sonucu bildir** (kısa): ne eklendi, bu makinede bağlandı mı (sync çıktısındaki BAĞLANDI/AYNA/HATA satırları), diğer makinelere en geç bir saat içinde gideceği ve Claude'un yeni oturumda göreceği.

## Kaldırma

`~/.agents/agent-skills/skill-add.sh remove <ad> [<ad> …]` — tüm makinelerden ve araçlardan en geç bir saatte kalkar. Ad emin değilsen önce `list` çalıştır.

## Listeleme

`~/.agents/agent-skills/skill-add.sh list` — manifest'teki skill adları. Makinede manifest dışından kurulmuş skill'ler için `ls ~/.agents/skills`.

## Hatalar

- **push başarısız:** Bu makinenin GitHub'a yazma izni yok. Değişiklik geri alınmıştır. Kullanıcıya `gh auth setup-git` ya da GitHub SSH anahtarı eklemesini söyle, ya da başka bir makineden eklemeyi öner.
- **klonlanamadı:** Repo adı yanlış ya da private. Private ise `git@github.com:owner/repo.git` biçimiyle tekrar dene.
- **skills.txt'te yerel değişiklik var:** Script durur. Değişikliği kullanıcıya göster; kendi başına geri alma.
