#!/bin/sh

# ci_post_clone.sh
# Executado pelo Xcode Cloud logo após clonar o repositório.
# Instala o XcodeGen e gera o .xcodeproj automaticamente.

set -e

echo "▶ Instalando Homebrew (se necessário)..."
which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo "▶ Instalando XcodeGen..."
brew install xcodegen

echo "▶ Gerando PPPIX.xcodeproj..."
cd $CI_WORKSPACE
xcodegen generate --spec project.yml

echo "✅ PPPIX.xcodeproj gerado com sucesso!"
ls -la *.xcodeproj
