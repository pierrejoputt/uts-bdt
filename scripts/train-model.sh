#!/bin/bash
# Melatih model di dalam container Python 3.12 dengan versi library yang sama dengan API
# (tidak perlu install Python/scikit-learn di laptop). Jalankan dari root repo.
set -e
cd "$(dirname "$0")/.."
mkdir -p api/model
# MSYS_NO_PATHCONV=1 mencegah Git Bash mengubah path /w menjadi path Windows
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd)":/w -w /w python:3.12-slim bash -c \
  "pip install --no-cache-dir -q 'scikit-learn==1.5.2' 'joblib==1.4.2' && python train.py"
ls -l api/model/model.pkl
