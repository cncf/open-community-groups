//! Attendee check-in credential parsing and scan outcome classification.

use anyhow::Error;
use uuid::Uuid;

#[cfg(test)]
mod tests;

/// Prefix of the supported versioned check-in credential.
const CREDENTIAL_PREFIX: &str = "ocg-check-in:v1:";

/// Maximum accepted serialized credential length.
const MAX_CREDENTIAL_LEN: usize = 160;

/// Classifies a check-in database failure into a stable scanner rejection.
///
/// Returns `None` when the failure is not one of the known domain errors and
/// must be treated as internal.
pub(crate) fn classify_scan_error(err: &Error) -> Option<CheckInScanRejection> {
    let message = err
        .downcast_ref::<tokio_postgres::Error>()?
        .as_db_error()
        .map(tokio_postgres::error::DbError::message)?;

    CheckInScanRejection::from_db_message(message)
}

/// Parses a versioned attendee credential into event and code identifiers.
pub(crate) fn parse_credential(credential: &str) -> Result<ScannedCredential, InvalidCredential> {
    // Reject oversized payloads before parsing
    if credential.len() > MAX_CREDENTIAL_LEN {
        return Err(InvalidCredential);
    }

    // Require the supported version and exactly two identifiers
    let payload = credential.strip_prefix(CREDENTIAL_PREFIX).ok_or(InvalidCredential)?;
    let (event_id, check_in_code) = payload.split_once(':').ok_or(InvalidCredential)?;
    if check_in_code.contains(':') {
        return Err(InvalidCredential);
    }

    Ok(ScannedCredential {
        check_in_code: check_in_code.parse().map_err(|_| InvalidCredential)?,
        event_id: event_id.parse().map_err(|_| InvalidCredential)?,
    })
}

// Types.

/// Stable scanner rejections raised by the check-in database function.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CheckInScanRejection {
    /// The attendee no longer has confirmed attendance.
    NonConfirmedAttendance,
    /// The event is not available for check-in.
    UnavailableEvent,
    /// The check-in credential is not recognized.
    UnknownCode,
}

impl CheckInScanRejection {
    /// Maps a database domain error message to its rejection.
    pub(crate) fn from_db_message(message: &str) -> Option<Self> {
        match message {
            "attendance is not confirmed" => Some(Self::NonConfirmedAttendance),
            "check-in credential not found" => Some(Self::UnknownCode),
            "event unavailable for check-in" => Some(Self::UnavailableEvent),
            _ => None,
        }
    }
}

/// The scanned credential is not a valid versioned check-in credential.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct InvalidCredential;

/// Identifiers decoded from a versioned check-in credential.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct ScannedCredential {
    /// Attendee check-in code.
    pub check_in_code: Uuid,
    /// Event the credential belongs to.
    pub event_id: Uuid,
}
