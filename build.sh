#!/bin/bash
# Compila o Alterna, monta o Alterna.app, instala em /Applications e abre.
#   bash build.sh               compila, instala e abre
#   bash build.sh --no-install  só compila e monta em build/
set -euo pipefail
cd "$(dirname "$0")"

# Assinatura fixa: com ela o macOS reconhece o app como "o mesmo" a cada nova versão
# e não pede de novo Acessibilidade, Acesso Total ao Disco, Automação etc.
IDENTITY="Alterna Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

ensure_identity() {
    if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
        return 0
    fi
    echo "› Criando certificado local de assinatura (uma vez só)…"
    local tmp
    tmp="$(mktemp -d)"
    cat > "$tmp/cert.cfg" <<'CFG'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Alterna Local Signing
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cfg" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -name "$IDENTITY" -out "$tmp/identity.p12" -passout pass:alterna 2>/dev/null
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P alterna -T /usr/bin/codesign >/dev/null
    rm -rf "$tmp"

    # A assinatura mudou: limpa as permissões antigas (feitas para a assinatura anterior)
    # para o macOS pedir uma última vez, já valendo para as próximas versões.
    tccutil reset All app.alterna.Alterna >/dev/null 2>&1 || true
    echo "  Certificado criado. Conceda as permissões do Alterna mais uma vez; depois elas ficam salvas."
}

echo "› Compilando (release)…"
swift build -c release

BIN=".build/release/Alterna"
APP="build/Alterna.app"

echo "› Montando ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Alterna"
cp Support/Info.plist "$APP/Contents/Info.plist"
make_icon() {
    # Gera o .icns com as ferramentas da Apple (sips + iconutil) a partir do PNG 1024.
    local set="build/AppIcon.iconset"
    rm -rf "$set"; mkdir -p "$set"
    for s in 16 32 128 256 512; do
        sips -z $s $s Support/AppIcon-1024.png --out "$set/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) Support/AppIcon-1024.png --out "$set/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$set" -o "$APP/Contents/Resources/AppIcon.icns" && rm -rf "$set"
}
make_icon || cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "› Assinando…"
ensure_identity
if codesign --force --sign "$IDENTITY" "$APP"; then
    echo "  Assinado com \"${IDENTITY}\" (permissões ficam salvas entre versões)."
else
    echo "  Não deu para usar o certificado local; assinando ad-hoc (o macOS pode pedir permissões de novo)."
    codesign --force --sign - "$APP"
fi

if [ "${1:-}" = "--no-install" ]; then
    echo "Pronto: $(pwd)/${APP}"
    exit 0
fi

echo "› Instalando em /Applications…"
pkill -x Alterna 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Alterna.app
cp -R "$APP" /Applications/Alterna.app
# Faz o Finder e o Dock lerem o ícone novo.
touch /Applications/Alterna.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Alterna.app 2>/dev/null || true
killall Dock 2>/dev/null || true
open /Applications/Alterna.app

echo ""
echo "Pronto! O Alterna foi instalado e aberto."
