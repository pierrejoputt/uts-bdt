#!/bin/bash
# Pengujian end-to-end untuk docker compose. Jalankan dari root repo setelah `docker compose up -d`.
# Output disimpan ke docs/evidence/compose-test.txt (bahan laporan).
cd "$(dirname "$0")/.."
mkdir -p docs/evidence
OUT=docs/evidence/compose-test.txt
API="${API:-http://localhost:${API_PORT:-8000}}"
export KC_URL="${KC_URL:-http://localhost:${KC_PORT:-8080}}"

{
echo "=== Waktu: $(date) ==="

echo; echo "### 1. Replikasi: pg_stat_replication di primary"
docker compose exec -T db-primary psql -U postgres -c "SELECT client_addr,state FROM pg_stat_replication;"

echo; echo "### 2. Replica dalam mode recovery (harus t)"
docker compose exec -T db-replica psql -U postgres -c "SELECT pg_is_in_recovery();"

echo; echo "### Menunggu Keycloak & API siap..."
for i in $(seq 1 45); do
  if curl -s -f -o /dev/null "$KC_URL/realms/uts" && curl -s -f -o /dev/null "$API/health"; then
    echo "Keycloak & API siap!"
    break
  fi
  sleep 2
done

echo; echo "### 3. Ambil token dari Keycloak"
TOKEN=$(scripts/get-token.sh)
if [ -z "$TOKEN" ]; then echo "GAGAL ambil token (Keycloak belum siap / realm belum ter-import)"; exit 1; fi
echo "token panjang: ${#TOKEN} karakter"

echo; echo "### 4. POST /predict dengan token (write -> primary)"
curl -s -X POST $API/predict -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"features":[5.1,3.5,1.4,0.2]}'; echo
sleep 1

echo; echo "### 5. GET /history dengan token (read -> replica, harus served_by_replica:true)"
curl -s $API/history -H "Authorization: Bearer $TOKEN"; echo

echo; echo "### 6. Tanpa token (harus 401)"
curl -s -o /dev/null -w "HTTP %{http_code}\n" $API/history

echo; echo "### 7. Token signature diubah (harus 401)"
BAD="${TOKEN:0:${#TOKEN}-20}AAAAAAAAAAAAAAAAAAAA"
curl -s -o /dev/null -w "HTTP %{http_code}\n" $API/history -H "Authorization: Bearer $BAD"

echo; echo "### 8. Token valid (harus 200)"
curl -s -o /dev/null -w "HTTP %{http_code}\n" $API/history -H "Authorization: Bearer $TOKEN"

if [ "$1" = "--expired" ]; then
  echo; echo "### 9. Token kedaluwarsa: tunggu 125 detik (accessTokenLifespan realm = 120 dtk)"
  sleep 125
  curl -s -o /dev/null -w "HTTP %{http_code} (harus 401)\n" $API/history -H "Authorization: Bearer $TOKEN"
fi
} 2>&1 | tee "$OUT"
echo; echo "Hasil tersimpan di $OUT"
