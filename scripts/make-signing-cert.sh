#!/bin/zsh
# Crea, una sola vez, un certificado local para firmar build/TCGPartner.app.
#
# Con la firma ad-hoc, cada compilación es "otra app" para macOS y el llavero vuelve a pedir permiso
# para leer la sesión de Supabase. Firmando siempre con este certificado, macOS la reconoce como la
# misma app y el "Permitir siempre" se conserva entre compilaciones.
#
# El certificado es autofirmado y solo vale en esta Mac. Se marca como de confianza solo para
# firmar código (no para webs ni correo). macOS pedirá tu contraseña para eso.
set -euo pipefail

NAME="TCG Partner Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "✅ El certificado «$NAME» ya existe y es válido. No hay nada que hacer."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  # Quedó a medias en un intento anterior: solo falta la confianza.
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$TMP/cert.pem"
else
  cat > "$TMP/cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  # LibreSSL de macOS: su .p12 lo entiende `security import` (el de OpenSSL 3 no, sin -legacy).
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
  PASS=$(/usr/bin/openssl rand -hex 16)
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS"
  # -T: codesign puede usar la llave sin preguntar cada vez.
  security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
  echo "Certificado creado en tu llavero."
fi

echo "Marcándolo como de confianza para firmar código (macOS pedirá tu contraseña)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "✅ Listo. ./scripts/build-app.sh firmará con «$NAME»."
else
  echo "❌ El certificado no quedó válido para firmar. Revisa en Acceso a Llaveros." >&2
  exit 1
fi
