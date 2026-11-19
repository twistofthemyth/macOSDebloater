#!/bin/bash
# Debloat persistence: переприменяет launchctl disable при каждой загрузке
# (macOS с SIP сбрасывает overrides на буте — поэтому нужен этот агент)
set -u
LOG=/var/log/debloat-persist.log
exec >> "$LOG" 2>&1
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
  com.apple.diagnosticextensionsd
  com.apple.spindump
  com.apple.tailspind
  com.apple.ReportCrash
  com.apple.OSDUIHelper
  com.apple.adid
  com.apple.newsd
  com.apple.AirPlayUIAgent
  com.apple.airplayd
  com.apple.ScreenTimeAgent
  com.apple.helpd
  com.apple.stocks
  com.apple.stocks.widget
  com.apple.seedutil
)

for label in "${DISABLE_LABELS[@]}"; do
  for domain in system gui/501; do
    launchctl disable "$domain/$label" 2>/dev/null && echo "disabled: $domain/$label"
    # уже запущенное прибиваем
    launchctl print "$domain/$label" >/dev/null 2>&1 && launchctl bootout "$domain/$label" 2>/dev/null
  done
done

# Spotlight убедимся что выключен (на случай если macOS переиндексирует после обновления)
mdutil -a -d >/dev/null 2>&1

echo "=== done: $(date) ==="
