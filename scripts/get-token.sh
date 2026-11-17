#!/bin/bash
# Mencetak access_token dari Keycloak (tanpa jq, kompatibel Git Bash).
# Pakai: TOKEN=$(scripts/get-token.sh)
# Variabel opsional: KC_URL (default http://localhost:8080), KC_USER, KC_PASS, KC_HOST_RESOLVE (untuk k8s)
cd "$(dirname "$0")/.."
KC_URL="${KC_URL:-http://localhost:${KC_PORT:-8080}}"
KC_USER="${KC_USER:-user1}"
KC_PASS="${KC_PASS:-user1pass}"
EXTRA=()
[ -n "$KC_HOST_RESOLVE" ] && EXTRA=(--resolve "$KC_HOST_RESOLVE")

curl -s "${EXTRA[@]}" \
  -d "client_id=uts-client" -d "username=$KC_USER" -d "password=$KC_PASS" \
  -d "grant_type=password" \
  "$KC_URL/realms/uts/protocol/openid-connect/token" \
  | sed -n 's/.*"access_token"[ ]*:[ ]*"\([^"]*\)".*/\1/p'
