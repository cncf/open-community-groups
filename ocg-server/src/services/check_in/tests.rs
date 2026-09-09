use uuid::Uuid;

use super::{CheckInScanRejection, InvalidCredential, ScannedCredential, parse_credential};

#[test]
fn test_check_in_scan_rejection_from_db_message_maps_known_messages() {
    // Map every stable database domain message
    assert_eq!(
        CheckInScanRejection::from_db_message("attendance is not confirmed"),
        Some(CheckInScanRejection::NonConfirmedAttendance)
    );
    assert_eq!(
        CheckInScanRejection::from_db_message("check-in credential not found"),
        Some(CheckInScanRejection::UnknownCode)
    );
    assert_eq!(
        CheckInScanRejection::from_db_message("event unavailable for check-in"),
        Some(CheckInScanRejection::UnavailableEvent)
    );

    // Check unrelated messages stay internal
    assert_eq!(CheckInScanRejection::from_db_message("boom"), None);
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
fn test_parse_credential_rejects_extra_fields() {
    // Setup a credential carrying an unexpected field
    let event_id = Uuid::from_u128(1);
    let check_in_code = Uuid::from_u128(2);

    // Parse and reject the credential
    assert_eq!(
        parse_credential(&format!("ocg-check-in:v1:{event_id}:{check_in_code}:extra")),
        Err(InvalidCredential)
    );
}

#[test]
fn test_parse_credential_rejects_oversized_payload() {
    // Parse and reject a credential longer than the accepted maximum
    let credential = format!("ocg-check-in:v1:{}", "a".repeat(200));
    assert_eq!(parse_credential(&credential), Err(InvalidCredential));
}

#[test]
fn test_parse_credential_rejects_unknown_version() {
    // Parse and reject an unsupported credential version
    assert_eq!(
        parse_credential(
            "ocg-check-in:v2:00000000-0000-0000-0000-000000000001:00000000-0000-0000-0000-000000000002"
        ),
        Err(InvalidCredential)
    );
}
