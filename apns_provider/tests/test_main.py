from main import PushRequest, build_apns_headers, build_apns_payload


def test_critical_payload_uses_critical_interruption_level():
    request = PushRequest(
        device_token="abc123",
        event_type="Baby crying detected",
        severity="critical",
        confidence=0.95,
        event_id="event-1",
        metadata={"classification": "crying"},
    )

    payload = build_apns_payload(request, notification_id="APNS-ID")

    assert payload["aps"]["alert"]["title"] == "Critical baby alert"
    assert payload["aps"]["interruption-level"] == "critical"
    assert payload["aps"]["category"] == "BABY_ALERT"
    assert payload["event_id"] == "event-1"
    assert payload["metadata"]["classification"] == "crying"


def test_warning_payload_defaults_event_id_and_time_sensitive_delivery():
    request = PushRequest(
        device_token="abc123",
        event_type="Nursery humidity high",
        severity="warning",
        confidence=0.74,
    )

    payload = build_apns_payload(request, notification_id="APNS-ID")

    assert payload["aps"]["alert"]["title"] == "Baby monitor warning"
    assert payload["aps"]["interruption-level"] == "time-sensitive"
    assert payload["event_id"] == "APNS-ID"
    assert payload["metadata"] == {}


def test_headers_set_apns_priority_by_severity():
    critical = PushRequest(device_token="abc123", event_type="Cry", severity="critical")
    warning = PushRequest(device_token="abc123", event_type="Noise", severity="warning")

    critical_headers = build_apns_headers("token", critical, notification_id="one")
    warning_headers = build_apns_headers("token", warning, notification_id="two")

    assert critical_headers["authorization"] == "bearer token"
    assert critical_headers["apns-priority"] == "10"
    assert warning_headers["apns-priority"] == "5"
    assert warning_headers["apns-topic"] == "wcs.BabyMont"
