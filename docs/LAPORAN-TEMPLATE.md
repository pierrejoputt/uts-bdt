# Kerangka Laporan (laporan.pdf)

Tulis ulang dengan kalimatmu sendiri. Tempel screenshot dari terminal dan isi `docs/evidence/*.txt`.

## 1. Pendahuluan
Tujuan, ringkasan sistem (API inferensi + PostgreSQL replikasi + SSO Keycloak), tautan repo Git.

## 2. Diagram Topologi
Render `docs/topology.mmd` (mermaid.live atau draw.io) lalu tempel gambarnya.
Tampilkan: Client, Ingress, API, Primary/Replica, Keycloak, PVC.

## 3. Keputusan Desain
- Async vs sync replication: yang dipakai async (default streaming). Konsekuensi: replica bisa tertinggal sedikit.
  Sync menjamin data sama tetapi write jadi lebih lambat / terblokir jika replica mati.
- Kenapa StatefulSet: identitas pod stabil (postgres-0/1), PVC per pod, urutan start terjamin.
- Kenapa Headless Service: DNS per pod (postgres-0.postgres-headless) agar replica menemukan primary.
- Service postgres-primary / postgres-replica: pembeda jalur write dan read.
- Keycloak + JWT (RS256, JWKS): API stateless, tidak menyimpan password.

## 4. Hubungan dengan Teori
- Replication transparency -> read routing: klien memanggil /history tanpa tahu data dibaca dari replica.
- Physical data independence -> PVC: data tetap ada walau pod dihapus/dipindah.
- Location transparency -> DNS service name: akses DB lewat nama, bukan IP pod.

## 5. Bukti Pengujian
| No | Pengujian | Bukti |
|----|-----------|-------|
| 1 | Persistensi PVC (25%) | jumlah baris sebelum/sesudah delete postgres-0 |
| 2 | Replikasi berjalan | pg_stat_replication + served_by_replica:true |
| 3 | Failover pod replica | /predict tetap 200, /history pulih |
| 4 | DNS discovery | getent hosts postgres-primary |
| 5 | SSO | screenshot login Keycloak, jwt.io (iss, sub, exp), 401 vs 200 |
| 6 | Kegagalan token | token kedaluwarsa / signature diubah -> 401 |

## 6. Kendala dan Solusi
Contoh: issuer tidak cocok (KC_HOSTNAME), CRLF pada script .sh, port bentrok.

## 7. Kesimpulan
