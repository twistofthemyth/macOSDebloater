#!/bin/bash
# =============================================================================
# macOS 26 (Tahoe) Debloat
#
# Запуск:  sudo bash debloat-full.sh
# Откат:   см. раздел "ОТКАТ" в конце файла
#
# Что делает:
#   Этап 2 — настройки пользователя (Handoff, анимации, телеметрия)
#   Этап 3 — Spotlight: полная остановка индексации
#   Этап 4 — отключение фоновых служб Apple через launchctl
#   Этап 6 — Reduce Transparency / Reduce Motion
#   Этап 7 — лёгкая чистка (только если включено DEBLOAT_CLEAN=1)
#   Демон  — persistence: держит службы выключенными после перезагрузок
#            и обновлений macOS (SIP сбрасывает launchctl disable на буте)
# =============================================================================
set -u
LOG="$HOME/debloat-full.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== debloat-full: $(date) ==="

# Пользователь, запустивший sudo (для user-level defaults при запуске из-под рута)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
PERSIST_SCRIPT=/usr/local/sbin/debloat-persist.sh
PERSIST_PLIST=/Library/LaunchDaemons/local.debloat.persist.plist

# Список отключаемых служб. siriknowledged НЕ отключаем (осознанно, см. README).
DISABLE_LABELS=(
  # Siri-инфраструктура (Siri Requests уже выключены в настройках)
  com.apple.assistantd
  com.apple.assistant_service
  com.apple.siriactionsd
  # Apple Intelligence / контекст
  com.apple.contextstored
  com.apple.privatecloudcomputed
  com.apple.IntelligencePlatformComputeService
  com.apple.intelligenceplatformd
  # Подсказки macOS
  com.apple.tipsd
  # Game Center
  com.apple.gamed
  com.apple.gamecontrollerd
  # Телеметрия и диагностика
  com.apple.diagnosticextensionsd
  com.apple.spindump
  com.apple.tailspind
  com.apple.ReportCrash
  com.apple.OSDUIHelper
  # Реклама / идентификаторы
  com.apple.adid
  com.apple.iad.darwin
  # Stocks / News
  com.apple.stocks
  com.apple.stocks.widget
  com.apple.newsd
  # Бета-программа
  com.apple.seedutil
  # AirPlay-приёмник (если не транслируете на Mac)
  com.apple.AirPlayUIAgent
  com.apple.airplayd
  # Screen Time
  com.apple.ScreenTimeAgent
  # Справка (Help Viewer)
  com.apple.helpd
)

# ---------------------------------------------------------------------------
# Этап 2 — настройки пользователя
# ---------------------------------------------------------------------------
echo "--- Этап 2: настройки пользователя ($REAL_USER) ---"
# Handoff OFF (гасит duetexpertd — всплески CPU на Tahoe)
sudo -u "$REAL_USER" defaults -currentHost write com.apple.coreservices.useractivityd.plist ActivityAdvertisingAllowed -bool false
sudo -u "$REAL_USER" defaults -currentHost write com.apple.coreservices.useractivityd.plist ActivityReceivingAllowed -bool false
# Reduce Motion
sudo -u "$REAL_USER" defaults write com.apple.accessibility ReduceMotionEnabled -bool true
# Dock: автоскрытие, без анимаций, минимум эффектов
sudo -u "$REAL_USER" defaults write com.apple.dock autohide -bool true
sudo -u "$REAL_USER" defaults write com.apple.dock launchanim -bool false
sudo -u "$REAL_USER" defaults write com.apple.dock expose-animation-duration -float 0.1
sudo -u "$REAL_USER" defaults write com.apple.dock mineffect -string scale
# Окна: без анимации открытия/закрытия
sudo -u "$REAL_USER" defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
# Телеметрия (user level)
sudo -u "$REAL_USER" defaults write com.apple.SetupAssistant SeenAssistantOptIn -int 2 2>/dev/null
killall Dock 2>/dev/null || true

# ---------------------------------------------------------------------------
# Этап 3 — Spotlight off
# ---------------------------------------------------------------------------
echo "--- Этап 3: Spotlight off ---"
mdutil -a -d

# ---------------------------------------------------------------------------
# Этап 4 — отключение служб
# ---------------------------------------------------------------------------
echo "--- Этап 4: launchctl disable ---"
for label in "${DISABLE_LABELS[@]}"; do
  for domain in system "gui/$(id -u "$REAL_USER")"; do
    if launchctl print "$domain/$label" >/dev/null 2>&1; then
      launchctl bootout "$domain/$label" 2>/dev/null
      launchctl disable "$domain/$label" 2>/dev/null
      echo "disabled: $domain/$label"
    fi
  done
done

# ---------------------------------------------------------------------------
# Этап 6 — Reduce Transparency (домен universalaccess требует root,
# и запись идёт напрямую в plist пользователя — НЕ в домен рута)
# ---------------------------------------------------------------------------
echo "--- Этап 6: Reduce Transparency ---"
defaults write "$REAL_HOME/Library/Preferences/com.apple.universalaccess" reduceTransparency -bool true

# ---------------------------------------------------------------------------
# Этап 7 — лёгкая чистка (ВЫКЛЮЧЕНО по умолчанию)
# Запуск:  sudo DEBLOAT_CLEAN=1 bash debloat-full.sh
# ---------------------------------------------------------------------------
if [ "${DEBLOAT_CLEAN:-0}" = "1" ]; then
  echo "--- Этап 7: чистка ---"
  # Форсировать системные скрипты обслуживания
  periodic daily weekly monthly
  # Кэши пользователя старше 7 дней (только файлы, без рекурсивного rm -rf)
  find "$REAL_HOME/Library/Caches" -type f -mtime +7 -delete 2>/dev/null
  echo "чистка завершена"
else
  echo "--- Этап 7: пропущен (DEBLOAT_CLEAN не задан; диск чистый, 12 ГБ из 466) ---"
fi

# ---------------------------------------------------------------------------
# Демон persistence — держит отключённое отключённым после перезагрузок
# ---------------------------------------------------------------------------
echo "--- Установка демона persistence ---"
mkdir -p /usr/local/sbin

cat > "$PERSIST_SCRIPT" <<'PERSIST_EOF'
#!/bin/bash
# Автопереприменение launchctl disable (SIP сбрасывает overrides на буте)
set -u
exec >> /var/log/debloat-persist.log 2>&1
echo "=== $(date): re-applying disables ==="

DISABLE_LABELS=(
  com.apple.assistantd
  com.apple.assistant_service
  com.apple.siriactionsd
  com.apple.contextstored
  com.apple.privatecloudcomputed
  com.apple.IntelligencePlatformComputeService
  com.apple.intelligenceplatformd
  com.apple.tipsd
  com.apple.gamed
  com.apple.gamecontrollerd
  com.apple.diagnosticextensionsd
  com.apple.spindump
  com.apple.tailspind
  com.apple.ReportCrash
  com.apple.OSDUIHelper
  com.apple.adid
  com.apple.iad.darwin
  com.apple.stocks
  com.apple.stocks.widget
  com.apple.newsd
  com.apple.seedutil
  com.apple.AirPlayUIAgent
  com.apple.airplayd
  com.apple.ScreenTimeAgent
  com.apple.helpd
)

for label in "${DISABLE_LABELS[@]}"; do
  for domain in system gui/501; do
    launchctl disable "$domain/$label" 2>/dev/null && echo "disabled: $domain/$label"
    launchctl print "$domain/$label" >/dev/null 2>&1 && launchctl bootout "$domain/$label" 2>/dev/null
  done
done

# Spotlight: убедиться, что индексация не включилась обратно
mdutil -a -d >/dev/null 2>&1
echo "=== done: $(date) ==="
PERSIST_EOF
chmod 0755 "$PERSIST_SCRIPT"

cat > "$PERSIST_PLIST" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.debloat.persist</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/sbin/debloat-persist.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>StandardOutPath</key>
    <string>/var/log/debloat-persist.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/debloat-persist.log</string>
</dict>
</plist>
PLIST_EOF
chmod 0644 "$PERSIST_PLIST"
chown root:wheel "$PERSIST_PLIST"

launchctl bootout system/local.debloat.persist 2>/dev/null || true
launchctl bootstrap system "$PERSIST_PLIST"
launchctl kickstart -k system/local.debloat.persist

# ---------------------------------------------------------------------------
# Проверка
# ---------------------------------------------------------------------------
echo "--- Проверка ---"
mdutil -s /
launchctl print system/local.debloat.persist 2>/dev/null | grep -E "state = " | head -1
echo "=== Готово: $(date) ==="

# =============================================================================
# ОТКАТ
# =============================================================================
# Spotlight:            sudo mdutil -a -i on
# Службы (по одной):    sudo launchctl enable system/<label> && sudo launchctl kickstart -k system/<label>
# Демон persistence:    sudo launchctl bootout system/local.debloat.persist
#                       sudo rm /Library/LaunchDaemons/local.debloat.persist.plist /usr/local/sbin/debloat-persist.sh
# Настройки Dock/окон:  defaults delete com.apple.dock; defaults delete NSGlobalDomain NSAutomaticWindowAnimationsEnabled
# Handoff:              defaults -currentHost delete com.apple.coreservices.useractivityd.plist
# Прозрачность/движение: defaults delete com.apple.universalaccess reduceTransparency
#                        defaults delete com.apple.accessibility ReduceMotionEnabled
