#!/bin/bash
# Deploy ke Minikube / Kubernetes lokal. Jalankan dari root repo di terminal/Git Bash.
# Prasyarat: Minikube / Docker Desktop Kubernetes sudah aktif.
set -e
cd "$(dirname "$0")/.."

if command -v minikube &> /dev/null && minikube status &> /dev/null; then
  echo "[1/6] Mengaktifkan addon ingress di Minikube"
  minikube addons enable ingress || true
  echo "[2/6] Build image API ke dalam Docker milik Minikube"
  if [ ! -f api/model/model.pkl ]; then bash scripts/train-model.sh; fi
  eval "$(minikube docker-env --shell bash)"
  docker build -t uts-api:1.0 ./api
else
  CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
  echo "[1/6] Minikube tidak aktif, menggunakan cluster Kubernetes aktif ($CURRENT_CTX)"
  echo "[2/6] Build image API uts-api:1.0 lokal"
  if [ ! -f api/model/model.pkl ]; then bash scripts/train-model.sh; fi
  docker build -t uts-api:1.0 ./api
fi

echo "[3/6] ConfigMap realm Keycloak dari keycloak/uts-realm.json"
kubectl create configmap keycloak-realm --from-file=uts-realm.json=keycloak/uts-realm.json \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[4/6] Apply manifest"
kubectl apply -f k8s/

echo "[5/6] Tunggu pod Ready (bisa 2-4 menit pertama kali)"
kubectl rollout status statefulset/postgres --timeout=300s
kubectl rollout status deployment/keycloak --timeout=300s
kubectl rollout status deployment/api --timeout=300s

echo "[6/6] Status"
kubectl get pods,pvc,svc,ingress
echo
echo "Langkah berikutnya: pastikan hosts berisi auth.lokal & api.lokal (lihat README bagian Kubernetes)."
