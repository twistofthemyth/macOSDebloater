# macOS 26 Debloat

Убирает фоновые службы Apple, которые на старом железе дают основную нагрузку:
индексацию Spotlight, Siri/Apple Intelligence-агенты, телеметрию, лишние анимации.

**Проверено на:** MacBook Pro 2019 (Intel), macOS 26.7.3. 

---

## Состав

| Файл | Назначение |
|---|---|
| `debloat-full.sh` | Единый скрипт: все настройки + отключение служб + демон persistence |
| `debloat-persist.sh` | Только демон persistence (без настроек). Ставится в `/usr/local/sbin` — для повторного применения списка служб без полного прогона; в обычной работе не нужен |
| `README.md` | Этот файл |

## Что делает скрипт

### Настройки пользователя (безопасно, обратимо)
- **Handoff OFF** — гасит `duetexpertd`, известного всплесками CPU на Tahoe
- **Reduce Motion** и **Reduce Transparency** — разгружают GPU Intel
- Dock: автоскрытие, без анимации запуска, эффект «Scale» вместо «Гений»
- Отключение анимаций открытия/закрытия окон
- Телеметрия на уровне пользователя

### Spotlight
- Полная остановка индексации на всех томах (`mdutil -a -d`)
- Поиск по имени в Finder перестанет работать; `find`, `grep`, Alfred/Raycast — без изменений
- Включается обратно: `sudo mdutil -a -i on`

### Отключённые службы (25 шт., через `launchctl disable`)
Siri-агенты (`assistantd`, `assistant_service`, `siriactionsd`), Apple Intelligence
(`contextstored`, `privatecloudcomputed`, `IntelligencePlatform*`), Подсказки (`tipsd`),
Game Center, телеметрия и диагностика (`spindump`, `tailspind`, `ReportCrash`,
`diagnosticextensionsd`), рекламные идентификаторы (`adid`, `iad.darwin`),
Stocks/News-виджеты, бета-загрузки (`seedutil`), AirPlay-приёмник, Screen Time, справка (`helpd`).

**Осознанно НЕ отключается:**
- `siriknowledged` — macOS с SIP перезапускает его в течение секунд, борьба бесполезна;
  в простое ест ~0% CPU и 0,1% RAM
- `WindowServer`, `Finder`, `Dock`, `coreaudiod`, `securityd`, `trustd`,
  `softwareupdated`, `XprotectService` — их отключение ломает систему/безопасность
- SIP не трогается вообще

### Демон persistence
macOS с включённым SIP сбрасывает `launchctl disable` при каждой загрузке.
Скрипт устанавливает демон `local.debloat.persist`, который переприменяет
отключение при старте системы и далее каждые 5 минут.

Содержимое демона встроено в `debloat-full.sh` (раздел «Демон») и ставится
в `/usr/local/sbin/debloat-persist.sh`. Отдельный файл `debloat-persist.sh`
в этой папке — та же логика отдельно: нужен, только если хотите обновить
список служб без полного прогона всех настроек.

---

## Как пользоваться

### Запуск (обычный)
```bash
sudo bash debloat-full.sh
```
Понадобится пароль администратора один раз. Лог пишется в `~/debloat-full.log`.

### Запуск с чисткой диска (опционально)
```bash
sudo DEBLOAT_CLEAN=1 bash debloat-full.sh
```
Дополнительно: форсирует системные скрипты обслуживания и удаляет кэши
пользователя старше 7 дней. На машине со свежей системой не нужно.

### После запуска
Перезагрузите Mac — уже запущенные процессы отключённых служб выгрузятся,
система стартует в чистой конфигурации.

### После обновлений macOS
macOS может вернуть часть служб и включить Spotlight обратно. Демон persistence
восстановит большинство сам; Spotlight при необходимости повторите:
```bash
sudo mdutil -a -d
```

---

## Откат

```bash
# Spotlight
sudo mdutil -a -i on

# Одна служба
sudo launchctl enable system/<label> && sudo launchctl kickstart -k system/<label>

# Демон persistence
sudo launchctl bootout system/local.debloat.persist
sudo rm /Library/LaunchDaemons/local.debloat.persist.plist /usr/local/sbin/debloat-persist.sh

# Настройки
defaults delete com.apple.dock
defaults delete NSGlobalDomain NSAutomaticWindowAnimationsEnabled
defaults -currentHost delete com.apple.coreservices.useractivityd.plist
defaults delete com.apple.universalaccess reduceTransparency
defaults delete com.apple.accessibility ReduceMotionEnabled
killall Dock
```

---

## Ограничения

- **SIP включён** — это осознанный выбор: безопасность важнее добивания
  последних пары процессов. `siriknowledged` и `spindump` могут жить в фоне,
  но в простое не мешают
- Протестировано на Intel; на Apple Silicon часть меток отсутствует — скрипт
  их просто пропустит
- Apple Music/TV/Photos/Почту скрипт не отключает — если ими не пользуетесь,
  закомментируйте в списке `DISABLE_LABELS`

## Логи
- `~/debloat-full.log` — основной запуск
- `/var/log/debloat-persist.log` — работа демона
