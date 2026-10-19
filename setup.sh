#!/usr/bin/env bash
# Prepara el proyecto Xcode de Coro en tu Mac.
set -euo pipefail
cd "$(dirname "$0")"

# /usr/bin/xcodebuild existe siempre (es un shim); solo -version falla si no hay Xcode de verdad.
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ Necesitas Xcode 26 o superior (App Store). Después:"
  echo "   sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "→ Instalando XcodeGen con Homebrew…"
    brew install xcodegen
  else
    echo "❌ Instala Homebrew (https://brew.sh) o XcodeGen (https://github.com/yonaskolb/XcodeGen) y vuelve a ejecutar."
    exit 1
  fi
fi

if [ ! -f Config.xcconfig ]; then
  cp Config.xcconfig.example Config.xcconfig
  echo "→ Creado Config.xcconfig. Rellena SPOTIFY_CLIENT_ID (y opcionalmente DEVELOPMENT_TEAM)."
fi

echo "→ Ejecutando tests del núcleo (CoroKit)…"
(cd CoroKit && swift test) || echo "⚠️  Fallaron tests de CoroKit; revisa la salida de arriba."

echo "→ Generando Coro.xcodeproj…"
xcodegen generate

echo "✅ Listo. Abriendo Xcode…"
open Coro.xcodeproj
