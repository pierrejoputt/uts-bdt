# UTS BDT: API Inferensi ML + PostgreSQL Replikasi + Keycloak SSO

Stack: FastAPI (model Iris) -> PostgreSQL streaming replication (primary/replica) -> Keycloak (OIDC/JWT).
Dijalankan dengan Docker Compose (Tahap 1) lalu Kubernetes/Minikube (Tahap 2).

Semua perintah di bawah bisa dijalankan di **terminal Linux/macOS** maupun **Git Bash (Windows)**
dari folder root repo (`uts-bdt/`). Catatan khusus Windows ditandai **[Windows]**.

## 0. Prasyarat

| Alat | Cek dengan |
|------|-----------|
| Docker Desktop (aktif) | `docker version` dan `docker compose version` |
| Git (Git Bash di Windows) | `git --version` |
| Minikube + kubectl (Tahap 2) | `minikube version` dan `kubectl version --client` |
| curl | `curl --version` |

Port bebas: 8000 (API), 8080 (Keycloak). Tidak perlu `jq`, Python, atau scikit-learn di laptop.

**[Windows] Penting sebelum clone/copy repo:** file `.sh` harus berakhiran baris LF, bukan CRLF.
Repo ini sudah punya `.gitattributes` yang memaksa LF. Jika tetap error `bad interpreter` / `\r: command not found`:
```bash
git config core.autocrlf false
sed -i 's/\r$//' scripts/*.sh db/*.sh
```

## 1. Persiapan awal

```bash
cd uts-bdt
bash scripts/init-env.sh          # membuat .env berisi password acak (jangan di-commit)
bash scripts/train-model.sh       # melatih model -> api/model/model.pkl (lewat container)
```

Alternatif manual untuk `.env`:
```bash
cp .env.example .env              # lalu edit password-nya
```

## 2. Tahap 1: Docker Compose

```bash
docker compose up -d --build
docker compose ps                 # semua service harus Up
docker compose logs -f db-replica # tunggu pg_basebackup selesai, Ctrl+C untuk keluar
```

Realm Keycloak (`uts`), client (`uts-client`) dan user (`user1` / `user1pass`) sudah ter-import otomatis
dari `keycloak/uts-realm.json`. Tunggu sekitar 30-60 detik sampai Keycloak siap:
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/realms/uts   # harus 200
```

### Verifikasi replikasi
```bash
docker compose exec db-primary psql -U postgres -c "SELECT client_addr,state FROM pg_stat_replication;"
docker compose exec db-replica psql -U postgres -c "SELECT pg_is_in_recovery();"   # harus t
```
**[Windows/Git Bash]** jika muncul error terminal "the input device is not a TTY", tambahkan `-T`
setelah `exec` (contoh: `docker compose exec -T db-primary psql ...`).

### Uji end-to-end manual
```bash
TOKEN=$(bash scripts/get-token.sh)
echo "$TOKEN" | cut -c1-40

curl -X POST localhost:8000/predict -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"features":[5.1,3.5,1.4,0.2]}'
curl localhost:8000/history -H "Authorization: Bearer $TOKEN"     # served_by_replica harus true
curl -i localhost:8000/history                                     # tanpa token -> 401
```
Token berlaku **120 detik** (`accessTokenLifespan` di realm JSON). Ambil ulang jika kedaluwarsa.

### Uji otomatis (hasil disimpan ke `docs/evidence/compose-test.txt`)
```bash
bash scripts/test-compose.sh             # cepat
bash scripts/test-compose.sh --expired   # plus uji token kedaluwarsa (menunggu ~2 menit)
```

### Reset total (hapus semua data)
```bash
docker compose down -v
```

## 3. Tahap 2: Kubernetes (Minikube)

Hentikan Compose dulu agar resource lega: `docker compose down`.

```bash
minikube start --driver=docker --memory=4096 --cpus=2
bash scripts/k8s-up.sh
```
Script itu mengerjakan: enable ingress, build image `uts-api:1.0` di Docker milik Minikube,
membuat ConfigMap realm, `kubectl apply -f k8s/`, dan menunggu pod siap.

Cek manual:
```bash
kubectl get pods,pvc,svc,ingress
kubectl logs postgres-1 --tail=20
```

### Akses lewat host `auth.lokal` dan `api.lokal`

Issuer token harus sama persis dengan `OIDC_ISSUER` (`http://auth.lokal/realms/uts`), jadi gunakan nama host ini.

**Linux / macOS (driver non-docker) atau Linux:**
```bash
echo "$(minikube ip) auth.lokal api.lokal" | sudo tee -a /etc/hosts
```

**[Windows] / driver Docker di Windows & macOS:**
1. Buka Git Bash **sebagai Administrator**, jalankan:
   ```bash
   echo "127.0.0.1 auth.lokal api.lokal" >> /c/Windows/System32/drivers/etc/hosts
   ```
2. Di terminal lain biarkan berjalan terus: `minikube tunnel` (mungkin minta izin admin).

Uji manual:
```bash
TOKEN=$(KC_URL=http://auth.lokal bash scripts/get-token.sh)
curl -X POST http://api.lokal/predict -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"features":[5.1,3.5,1.4,0.2]}'
curl http://api.lokal/history -H "Authorization: Bearer $TOKEN"
```

### Uji otomatis sesuai rubrik (hasil: `docs/evidence/k8s-test.txt`)
```bash
# Linux/macOS non-docker driver:
bash scripts/test-k8s.sh
# Windows/macOS driver docker (minikube tunnel aktif):
INGRESS_IP=127.0.0.1 bash scripts/test-k8s.sh
```
Script mencakup: SSO (401 vs 200), token rusak, replikasi, persistensi PVC (delete `postgres-0`),
failover replica (delete `postgres-1`), dan DNS discovery (`getent hosts`).

Perintah manual untuk screenshot laporan:
```bash
kubectl exec postgres-0 -- psql -U postgres -d appdb -c "SELECT count(*) FROM inference_history;"
kubectl delete pod postgres-0
kubectl get pod postgres-0 -w        # tunggu Running 1/1, Ctrl+C
kubectl exec postgres-0 -- psql -U postgres -d appdb -c "SELECT count(*) FROM inference_history;"
kubectl exec deploy/api -- getent hosts postgres-primary
```

### Bersih-bersih
```bash
kubectl delete -f k8s/ && kubectl delete configmap keycloak-realm
kubectl delete pvc -l app=postgres       # hapus data
minikube stop                            # atau: minikube delete
```

## 4. Push ke Git
```bash
git init && git add . && git status      # pastikan .env TIDAK ikut
git commit -m "UTS BDT: API + replikasi PostgreSQL + Keycloak + K8s"
git branch -M main
git remote add origin <URL-REPO-ANDA>
git push -u origin main
```
`api/model/model.pkl` ikut di-commit agar repo bisa langsung di-build.

## 5. Troubleshooting

| Gejala | Penyebab / solusi |
|--------|-------------------|
| `401 Token tidak valid` padahal token baru | Issuer tidak cocok. Compose: ambil token dari `http://localhost:8080`. K8s: dari `http://auth.lokal`. Cek isi `iss` di jwt.io. |
| `bad interpreter` / `\r` pada script .sh | CRLF. Jalankan `sed -i 's/\r$//' scripts/*.sh db/*.sh`. |
| `db-replica` restart terus | Cek `docker compose logs db-replica`. Biasanya `REPL_PASSWORD` di `.env` berubah setelah volume terbentuk. Reset: `docker compose down -v`. |
| `pg_stat_replication` kosong | Replica belum selesai basebackup, tunggu beberapa detik, lihat log replica. |
| `/history` kosong tepat setelah `/predict` | Replikasi async, ada jeda milidetik. Ulangi request. |
| `/history` 503 | Replica sedang mati/restart. Normal saat uji failover. |
| Keycloak `Account is not fully set up` | User butuh email, first name, last name (sudah ada di realm JSON). |
| Pod API `ErrImageNeverPull` | Image belum dibuild di Docker Minikube. Ulangi `eval "$(minikube docker-env --shell bash)"` lalu `docker build -t uts-api:1.0 ./api`. |
| `auth.lokal` tidak resolve | Hosts belum diedit atau `minikube tunnel` mati. Script `test-k8s.sh` tidak butuh hosts (memakai `--resolve`). |
| Port 8080/8000 terpakai | Hentikan proses lain atau ubah mapping port di `docker-compose.yml`. |
| Git Bash mengubah path `/w` jadi `C:/Program Files/Git/w` | Awali perintah dengan `MSYS_NO_PATHCONV=1`. |

## 6. Struktur repo
```
uts-bdt/
├── api/ (Dockerfile, requirements.txt, app/{main,auth,db}.py, model/model.pkl)
├── db/ (primary-init.sh, replica-entry.sh)
├── keycloak/uts-realm.json
├── k8s/ (00..40 *.yaml)
├── scripts/ (init-env, train-model, get-token, test-compose, k8s-up, test-k8s)
├── sql/001_schema.sql
├── docs/ (topology.mmd, LAPORAN-TEMPLATE.md, evidence/, screenshot, laporan.pdf)
├── docker-compose.yml, train.py, .env.example, .gitignore, .gitattributes
```

## Catatan keamanan (lab)
Password di `k8s/00-secret-config.yaml`, user `user1/user1pass`, dan admin Keycloak (`admin/admin` di K8s)
hanya untuk lab. Ganti sebelum dipakai di luar tugas kuliah.
