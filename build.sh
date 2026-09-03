#!/bin/bash
# Собирает TapShortcuts.app и подписывает его.
#
# Подпись нужна не ради безопасности: macOS привязывает к ней автозапуск
# и прочие выданные приложению права. Без неё они слетают при каждой пересборке.
set -euo pipefail
cd "$(dirname "$0")"

APP="TapShortcuts.app"
# Собираем во временной папке вне «Рабочего стола»: он синхронизируется с
# облаком, а файловый провайдер вешает атрибуты, которые codesign отвергает.
PROJECT="$(pwd)"
STAGE="$(mktemp -d /tmp/tapshortcuts-build.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
BIN="$STAGE/$APP/Contents/MacOS/TapShortcuts"

echo "==> сборка"
mkdir -p "$STAGE/$APP/Contents/MacOS" "$STAGE/$APP/Contents/Resources"
# main.swift обязан идти последним: Swift ищет точку входа именно в нём.
swiftc -O -o "$BIN" \
    $(ls Sources/*.swift | grep -v 'main\.swift$') Sources/main.swift \
    -framework AppKit -framework ServiceManagement
cp Info.plist "$STAGE/$APP/Contents/Info.plist"

xattr -cr "$STAGE/$APP"

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID|Apple Development/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
    echo "==> подпись ($IDENTITY)"
    codesign --force --deep --options runtime --sign "$IDENTITY" "$STAGE/$APP"
else
    echo "==> подпись сертификатом не найдена, подписываем локально"
    codesign --force --deep --sign - "$STAGE/$APP"
fi

if codesign --verify --strict "$STAGE/$APP" 2>/dev/null; then
    echo "==> подпись действительна"
else
    echo "==> ОШИБКА: подпись не прошла проверку"
    exit 1
fi

echo "==> установка"
rm -rf "$PROJECT/$APP"
ditto "$STAGE/$APP" "$PROJECT/$APP"
if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/$APP"
    ditto "$STAGE/$APP" "/Applications/$APP"
    echo "    /Applications/$APP"
fi
echo "Готово: $PROJECT/$APP"
