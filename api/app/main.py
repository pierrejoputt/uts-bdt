from pathlib import Path
import joblib
import psycopg
from fastapi import Depends, FastAPI, HTTPException
from psycopg.types.json import Jsonb

from .auth import current_user
from .db import PRIMARY, REPLICA, conn

app = FastAPI(title="UTS BDT - Iris Inference API")

MODEL_PATH = Path(__file__).resolve().parent.parent / "model" / "model.pkl"


def load_model():
    if not MODEL_PATH.exists():
        from sklearn.datasets import load_iris
        from sklearn.ensemble import RandomForestClassifier

        MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
        X, y = load_iris(return_X_y=True)
        clf = RandomForestClassifier(n_estimators=50, random_state=42).fit(X, y)
        joblib.dump(clf, MODEL_PATH)
        return clf
    return joblib.load(MODEL_PATH)


model = load_model()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/predict")
def predict(payload: dict, user=Depends(current_user)):
    try:
        features = payload.get("features")
        if not isinstance(features, list) or len(features) != 4:
            raise ValueError()
        pred = int(model.predict([features])[0])
    except Exception:
        raise HTTPException(422, 'Body harus berisi {"features": [4 angka]}')
    try:
        with conn(PRIMARY) as c:  # WRITE ROUTING -> primary
            c.execute(
                "INSERT INTO inference_history(user_sub,input,prediction) VALUES (%s,%s,%s)",
                (user["sub"], Jsonb(payload), pred),
            )
    except psycopg.Error:
        raise HTTPException(503, "Database primary tidak tersedia")
    return {"prediction": pred}


@app.get("/history")
def history(user=Depends(current_user)):
    try:
        with conn(REPLICA) as c:  # READ ROUTING -> replica
            rows = c.execute(
                "SELECT id,input,prediction,created_at FROM inference_history "
                "WHERE user_sub=%s ORDER BY id DESC LIMIT 20",
                (user["sub"],),
            ).fetchall()
            served_by = bool(c.execute("SELECT pg_is_in_recovery()").fetchone()[0])
    except psycopg.Error:
        raise HTTPException(503, "Database replica tidak tersedia")
    return {"served_by_replica": served_by, "rows": rows}
