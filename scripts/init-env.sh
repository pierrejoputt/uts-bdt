#!/bin/bash
# Membuat file .env (tidak di-commit) dengan password acak. Jalankan dari root repo.
set -e
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo ".env sudah ada, tidak ditimpa."
  exit 0
fi

rand() {
  if [ -r /dev/urandom ]; then
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-20
  else
    date +%s%N | sha256sum | head -c 20
  fi
}

cat > .env <<EOF
PG_PASSWORD=$(rand)
REPL_PASSWORD=$(rand)
KC_PASSWORD=$(rand)
API_PORT=8000
KC_PORT=8080
EOF
echo ".env dibuat."
