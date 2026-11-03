use uuid::Uuid;

use super::{
    CheckInScanRejection, InvalidCredential, MAX_CREDENTIAL_LEN, ScannedCredential,
    format_credential, parse_credential,
};

#[test]
fn test_check_in_scan_rejection_from_db_message_maps_known_messages() {
    // Map every stable database domain message and an unrelated one
    let cases = [
        (
            "attendance is not confirmed",
            Some(CheckInScanRejection::NonConfirmedAttendance),
        ),
        (
            "check-in credential not found",
            Some(CheckInScanRejection::UnknownCode),
        ),
        (
            "event unavailable for check-in",
            Some(CheckInScanRejection::UnavailableEvent),
        ),
        ("boom", None),
    ];
    for (message, expected) in cases {
        assert_eq!(
            CheckInScanRejection::from_db_message(message),
            expected,
            "{message}"
        );
    }
}

#[test]
fn test_format_credential_round_trips_through_parse_credential() {
    // Setup identifier pairs, including the boundary UUID values
    let cases = [
        (Uuid::from_u128(1), Uuid::from_u128(2)),
        (Uuid::nil(), Uuid::max()),
        (Uuid::max(), Uuid::nil()),
    ];

    // Parse every formatted credential back into its identifiers
    for (event_id, check_in_code) in cases {
        assert_eq!(
            parse_credential(&format_credential(event_id, check_in_code)),
            Ok(ScannedCredential {
                check_in_code,
                event_id,
            }),
            "{event_id}:{check_in_code}"
        );
    }
}

#[test]
fn test_format_credential_uses_versioned_wire_format() {
    // Format a credential with deterministic identifiers
    let credential = format_credential(Uuid::from_u128(1), Uuid::from_u128(2));

    // Check the literal the scanner parses and the accepted length bound
    assert_eq!(
        credential,
        "ocg-check-in:v1:00000000-0000-0000-0000-000000000001:00000000-0000-0000-0000-000000000002"
    );
    assert!(credential.len() <= MAX_CREDENTIAL_LEN);
}

#[test]
fn test_parse_credential_accepts_versioned_payload() {
    // Setup a versioned credential
    let event_id = Uuid::from_u128(1);
    let check_in_code = Uuid::from_u128(2);

    // Parse and verify the credential identifiers
    assert_eq!(
        parse_credential(&format!("ocg-check-in:v1:{event_id}:{check_in_code}")),
        Ok(ScannedCredential {
            check_in_code,
            event_id,
        })
    );
}

#[test]
fn test_parse_credential_rejects_invalid_payloads() {
    // Setup credentials that break each part of the versioned format
    let event_id = Uuid::from_u128(1);
    let check_in_code = Uuid::from_u128(2);
    let cases = [
        (
            "extra field",
            format!("ocg-check-in:v1:{event_id}:{check_in_code}:extra"),
        ),
        (
            "invalid check-in code",
            format!("ocg-check-in:v1:{event_id}:not-a-uuid"),
        ),
        (
            "invalid event id",
            format!("ocg-check-in:v1:not-a-uuid:{check_in_code}"),
        ),
        ("missing separator", format!("ocg-check-in:v1:{event_id}")),
        (
            "unknown version",
            format!("ocg-check-in:v2:{event_id}:{check_in_code}"),
        ),
    ];

    // Parse and reject every credential
    for (case, credential) in cases {
        assert_eq!(
            parse_credential(&credential),
            Err(InvalidCredential),
            "{case}"
        );
    }
}
