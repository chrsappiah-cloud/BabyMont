from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import httpx
import jwt
import os
import time
import uuid

app = FastAPI(title="BabyMont APNs Provider")

TEAM_ID = os.getenv("APNS_TEAM_ID", "YOUR_TEAM_ID")
KEY_ID = os.getenv("APNS_KEY_ID", "YOUR_KEY_ID")
BUNDLE_ID = os.getenv("APNS_BUNDLE_ID", "wcs.BabyMont")
TOKEN_AUTH_KEY_PATH = os.getenv("APNS_AUTH_KEY_PATH", "AuthKey_XXXXXXX.p8")
APNS_ENVIRONMENT = os.getenv("APNS_ENVIRONMENT", "sandbox")


class PushRequest(BaseModel):
    device_token: str
    event_type: str
    severity: str
    confidence: float = 0.0
    event_id: str | None = None
    metadata: dict[str, str] = Field(default_factory=dict)


def build_apns_payload(request: PushRequest, notification_id: str) -> dict:
    critical = request.severity == "critical"
    return {
        "aps": {
            "alert": {
                "title": "Critical baby alert" if critical else "Baby monitor warning",
                "body": f"{request.event_type} detected at {int(request.confidence * 100)}% confidence.",
            },
            "sound": "default",
            "category": "BABY_ALERT",
            "thread-id": "nursery-alerts",
            "interruption-level": "critical" if critical else "time-sensitive",
            "content-available": 1,
        },
        "event_id": request.event_id or notification_id,
        "event_type": request.event_type,
        "severity": request.severity,
        "confidence": request.confidence,
        "metadata": request.metadata,
    }


def build_apns_headers(token: str, request: PushRequest, notification_id: str) -> dict:
    critical = request.severity == "critical"
    return {
        "authorization": f"bearer {token}",
        "apns-topic": BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10" if critical else "5",
        "apns-id": notification_id,
    }


def apns_host() -> str:
    return "api.push.apple.com" if APNS_ENVIRONMENT == "production" else "api.sandbox.push.apple.com"


def make_token() -> str:
    with open(TOKEN_AUTH_KEY_PATH, "r", encoding="utf-8") as key_file:
        key = key_file.read()
    payload = {"iss": TEAM_ID, "iat": int(time.time())}
    headers = {"alg": "ES256", "kid": KEY_ID}
    return jwt.encode(payload, key, algorithm="ES256", headers=headers)


@app.post("/push")
async def send_push(request: PushRequest):
    token = make_token()
    host = apns_host()
    url = f"https://{host}/3/device/{request.device_token}"
    notification_id = str(uuid.uuid4()).upper()
    payload = build_apns_payload(request, notification_id)
    headers = build_apns_headers(token, request, notification_id)

    async with httpx.AsyncClient(http2=True, timeout=10) as client:
        response = await client.post(url, json=payload, headers=headers)
        if response.status_code >= 400:
            raise HTTPException(status_code=response.status_code, detail=response.text)

    return {"status": "sent", "apns_id": notification_id}
