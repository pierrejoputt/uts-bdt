# train.py - melatih model sederhana (Iris + RandomForest) lalu menyimpan ke api/model/model.pkl
# Jalankan lewat scripts/train-model.sh agar versi scikit-learn sama dengan di container API.
from sklearn.datasets import load_iris
from sklearn.ensemble import RandomForestClassifier
import joblib

X, y = load_iris(return_X_y=True)
joblib.dump(RandomForestClassifier(n_estimators=50, random_state=42).fit(X, y), "api/model/model.pkl")
print("model.pkl tersimpan di api/model/model.pkl")
