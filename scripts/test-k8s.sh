#!/bin/bash
# Pengujian sesuai rubrik (PVC, replikasi, failover, DNS, SSO, token gagal) di Kubernetes.
# Jalankan dari root repo. Output -> docs/evidence/k8s-test.txt
#
# INGRESS_IP: IP tujuan ingress.
#   - Linux / minikube driver non-docker : default `minikube ip`
#   - Windows/Mac driver docker          : jalankan `minikube tunnel` di terminal lain, lalu  export INGRESS_IP=127.0.0.1
# Dengan --resolve, file hosts TIDAK wajib diedit untuk menjalankan script ini.
cd "$(dirname "$0")/.."
mkdir -p docs/evidence
OUT=docs/evidence/k8s-test.txt

if [ -n "$INGRESS_IP" ]; then
  IP="$INGRESS_IP"
elif command -v minikube &> /dev/null && minikube status &> /dev/null; then
  IP="$(minikube ip 2>/dev/null || echo 127.0.0.1)"
else
  IP="127.0.0.1"
fi

RES=(--resolve "auth.lokal:80:$IP" --resolve "api.lokal:80:$IP")
API=http://api.lokal

psql_primary() { kubectl exec postgres-0 -- psql -U postgres -d appdb -Atc "$1"; }
pod_ready() {
  for i in $(seq 1 90); do
    [ "$(kubectl get pod "$1" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" = "true" ] && return 0
    sleep 2
  done
  return 1
}
get_token() { KC_URL=http://auth.lokal KC_HOST_RESOLVE="auth.lokal:80:$IP" scripts/get-token.sh; }

{
echo "=== Waktu: $(date) | INGRESS_IP=$IP ==="
kubectl get pods,pvc,svc,ingress

echo; echo "### SSO: ambil token via Keycloak (issuer http://auth.lokal/realms/uts)"
TOKEN=$(get_token)
[ -z "$TOKEN" ] && { echo "GAGAL ambil token. Cek ingress/hosts/tunnel & pod keycloak."; exit 1; }
echo "token OK (${#TOKEN} karakter)"
echo "Payload (tempel token ke jwt.io untuk screenshot; lihat iss, sub, exp):"
echo "$TOKEN" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null; echo

echo; echo "### SSO: tanpa token -> 401, dengan token -> 200"
curl -s "${RES[@]}" -o /dev/null -w "tanpa token : HTTP %{http_code}\n" $API/history
curl -s "${RES[@]}" -o /dev/null -w "dengan token : HTTP %{http_code}\n" $API/history -H "Authorization: Bearer $TOKEN"

echo; echo "### Kegagalan token: signature diubah"
BAD="${TOKEN:0:${#TOKEN}-20}AAAAAAAAAAAAAAAAAAAA"
curl -s "${RES[@]}" -o /dev/null -w "token rusak : HTTP %{http_code} (harus 401)\n" $API/history -H "Authorization: Bearer $BAD"

echo; echo "### Isi data awal: 3x POST /predict"
for f in "5.1,3.5,1.4,0.2" "6.7,3.1,4.7,1.5" "6.3,3.3,6.0,2.5"; do
  curl -s "${RES[@]}" -X POST $API/predict -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d "{\"features\":[$f]}"; echo
done
sleep 1

echo; echo "### Replikasi: pg_stat_replication di primary"
kubectl exec postgres-0 -- psql -U postgres -c "SELECT client_addr,state FROM pg_stat_replication;"
echo "pg_is_in_recovery di postgres-1 (harus t):"
kubectl exec postgres-1 -- psql -U postgres -Atc "SELECT pg_is_in_recovery();"
echo "GET /history (harus served_by_replica:true):"
curl -s "${RES[@]}" $API/history -H "Authorization: Bearer $TOKEN"; echo

echo; echo "### Persistensi PVC: hitung baris -> hapus postgres-0 -> hitung ulang"
BEFORE=$(psql_primary "SELECT count(*) FROM inference_history")
echo "Sebelum: $BEFORE baris"
kubectl delete pod postgres-0
pod_ready postgres-0 && echo "postgres-0 Running/Ready lagi"
sleep 3
AFTER=$(psql_primary "SELECT count(*) FROM inference_history")
echo "Sesudah: $AFTER baris  -> $([ "$BEFORE" = "$AFTER" ] && echo SAMA/LULUS || echo BEDA/GAGAL)"
kubectl get pvc

echo; echo "### Failover pod replica: hapus postgres-1"
kubectl delete pod postgres-1 --wait=false
sleep 2
echo "/predict saat replica mati (harus tetap 200):"
curl -s "${RES[@]}" -o /dev/null -w "HTTP %{http_code}\n" -X POST $API/predict -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"features":[5.0,3.6,1.4,0.2]}'
echo "/history saat replica mati (diharapkan 503):"
curl -s "${RES[@]}" -o /dev/null -w "HTTP %{http_code}\n" $API/history -H "Authorization: Bearer $TOKEN"
pod_ready postgres-1 && echo "postgres-1 kembali Ready"
sleep 5
echo "/history setelah pulih:"
curl -s "${RES[@]}" $API/history -H "Authorization: Bearer $TOKEN"; echo

echo; echo "### DNS discovery: API mengakses DB lewat hostname, bukan IP pod"
kubectl exec deploy/api -- getent hosts postgres-primary
kubectl exec deploy/api -- getent hosts postgres-replica
kubectl exec deploy/api -- getent hosts postgres-0.postgres-headless
} 2>&1 | tee "$OUT"
echo; echo "Hasil tersimpan di $OUT"
