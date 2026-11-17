"""Validasi JWT (OIDC) memakai JWKS dari Keycloak."""
import os
import jwt
from fastapi import Header, HTTPException
from jwt import PyJWKClient

JWKS_URL = os.environ.get(
    "JWKS_URL", "http://keycloak:8080/realms/uts/protocol/openid-connect/certs"
)
ISSUER = os.environ.get("OIDC_ISSUER", "http://localhost:8080/realms/uts")

jwks = PyJWKClient(JWKS_URL)


def current_user(authorization: str | None = Header(default=None)):
    # Header dibuat opsional supaya request tanpa token menghasilkan 401 (bukan 422).
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Token tidak ada")
    try:
        token = authorization.removeprefix("Bearer ").strip()
        key = jwks.get_signing_key_from_jwt(token).key
        return jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            issuer=ISSUER,
            options={"verify_aud": False},
        )
    except Exception:
        raise HTTPException(401, "Token tidak valid")
