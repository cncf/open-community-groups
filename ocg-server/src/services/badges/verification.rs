//! OCG badge credential proof and profile verification.

use chrono::{DateTime, Utc};
use serde_json::Value;
use uuid::Uuid;

use crate::{
    db::DBOperations,
    types::badges::{UserBadge, VerifiedBadge},
};

use super::{BadgesManagerError, DynBadgesManager, Result, badge_image_url, png};

// Types.

/// Expected invalid input or an operational verification failure.
#[derive(Debug, thiserror::Error)]
pub(crate) enum VerificationError {
    /// Server or database state prevented verification from completing.
    #[error(transparent)]
    Internal(anyhow::Error),
    /// User-supplied input is malformed, unknown, or cryptographically invalid.
    #[error("invalid badge credential")]
    Invalid,
}

/// Verified portable credential fields bound to local identifiers by handlers.
pub(crate) struct VerifiedCredential {
    /// Immutable badge description.
    pub description: String,
    /// Issuing group identifier.
    pub group_id: Uuid,
    /// Stable issuer URL.
    pub issuer: String,
    /// Immutable badge name.
    pub name: String,
    /// Stable revocation-list identifier.
    pub status_list_id: Uuid,
    /// Credential index in the referenced status list.
    pub status_list_index: i32,
    /// Opaque local award identifier.
    pub user_badge_id: Uuid,
    /// Credential award timestamp.
    pub valid_from: DateTime<Utc>,

    /// Exported hashed email identity carried by the credential, when present.
    pub email_identity: Option<VerifiedEmailIdentity>,
}

/// Exported hashed email identity claims carried by a verified credential.
pub(crate) struct VerifiedEmailIdentity {
    /// Hex digest extracted from the `sha256$`-prefixed identity hash.
    pub identity_hash: String,
    /// Salt appended to the bound lowercased email before hashing.
    pub salt: String,
}

// Submission verification.

/// Resolves and verifies one supported verification submission.
///
/// An uploaded Open Badges PNG is verified cryptographically and bound to its
/// persisted award; a local identifier or credential URL is resolved directly
/// from durable award state. Nothing is dereferenced from arbitrary URLs.
pub(crate) async fn verify_submission(
    badges_manager: &DynBadgesManager,
    db: &dyn DBOperations,
    credential_reference: Option<&str>,
    png_bytes: Option<&[u8]>,
) -> std::result::Result<VerifiedBadge, VerificationError> {
    // Prefer the uploaded portable credential over a local reference
    if let Some(png_bytes) = png_bytes {
        return verify_portable_credential(badges_manager, db, png_bytes).await;
    }

    resolve_credential_reference(badges_manager, db, credential_reference).await
}

/// Loads the durable award behind a verified or referenced local identifier.
async fn load_award(
    db: &dyn DBOperations,
    user_badge_id: Uuid,
) -> std::result::Result<UserBadge, VerificationError> {
    db.get_public_user_badge(user_badge_id)
        .await
        .map_err(VerificationError::Internal)?
        .ok_or(VerificationError::Invalid)
}

/// Classifies proof and profile failures without hiding server configuration faults.
fn map_verification_validation_error(error: BadgesManagerError) -> VerificationError {
    match error {
        error @ (BadgesManagerError::InvalidContext | BadgesManagerError::InvalidKey) => {
            VerificationError::Internal(error.into())
        }
        _ => VerificationError::Invalid,
    }
}

/// Prefers a public name while retaining the public username fallback.
fn recipient_display_name(name: Option<String>, username: Option<String>) -> Option<String> {
    name.or(username)
}

/// Resolves a local identifier or credential URL directly from durable award state.
async fn resolve_credential_reference(
    badges_manager: &DynBadgesManager,
    db: &dyn DBOperations,
    credential_reference: Option<&str>,
) -> std::result::Result<VerifiedBadge, VerificationError> {
    // Accept a bare award identifier or an allowlisted local credential URL
    let reference = credential_reference
        .map(str::trim)
        .filter(|reference| !reference.is_empty())
        .ok_or(VerificationError::Invalid)?;
    let user_badge_id = Uuid::parse_str(reference)
        .or_else(|_| badges_manager.parse_credential_url(reference))
        .map_err(|_| VerificationError::Invalid)?;

    // Describe the award from its persisted snapshot and status
    let award = load_award(db, user_badge_id).await?;
    Ok(VerifiedBadge {
        description: award.snapshot.description,
        image_url: badge_image_url(&award.snapshot.image_file_name),
        issuer: badges_manager.issuer_url(award.group_id),
        name: award.snapshot.name,
        revoked: award.revoked_at.is_some(),
        superseded: false,
        valid_from: award.awarded_at,

        recipient_name: recipient_display_name(award.recipient_name, award.recipient_username),
    })
}

/// Verifies an uploaded Open Badges PNG and binds it to its persisted award.
async fn verify_portable_credential(
    badges_manager: &DynBadgesManager,
    db: &dyn DBOperations,
    png_bytes: &[u8],
) -> std::result::Result<VerifiedBadge, VerificationError> {
    // Extract and cryptographically verify the baked credential
    let credential = png::extract(png_bytes).map_err(|_| VerificationError::Invalid)?;
    let credential =
        serde_json::from_slice::<Value>(&credential).map_err(|_| VerificationError::Invalid)?;
    let verified = badges_manager
        .verify_credential(&credential)
        .await
        .map_err(map_verification_validation_error)?;

    // Bind the verified claims to the durable award they reference
    let award = load_award(db, verified.user_badge_id).await?;
    if award.badge_status_list_id != verified.status_list_id
        || award.group_id != verified.group_id
        || award.status_list_index != verified.status_list_index
    {
        return Err(VerificationError::Invalid);
    }

    // Flag exports whose identity no longer matches the durable binding
    let superseded = verified.email_identity.as_ref().is_some_and(|identity| {
        award.identity_hash.as_deref() != Some(identity.identity_hash.as_str())
            || award.identity_salt.as_deref() != Some(identity.salt.as_str())
    });

    // Describe the award from the verified credential and its persisted status
    Ok(VerifiedBadge {
        description: verified.description,
        image_url: badge_image_url(&award.snapshot.image_file_name),
        issuer: verified.issuer,
        name: verified.name,
        revoked: award.revoked_at.is_some(),
        superseded,
        valid_from: verified.valid_from,

        recipient_name: recipient_display_name(award.recipient_name, award.recipient_username),
    })
}

// Credential profile helpers.

/// Returns whether an uploaded credential carries unsupported identifier claims.
///
/// The only supported identifier is a single OCG-exported hashed email
/// identity at `credentialSubject.identifier`; identifier claims anywhere
/// else, or any other shape at that location, remain rejected.
pub(super) fn contains_unsupported_identifier(credential: &Value) -> bool {
    // Validate the optional exported email identity at its only supported location
    let mut remainder = credential.clone();
    if let Some(subject) = remainder
        .pointer_mut("/credentialSubject")
        .and_then(Value::as_object_mut)
        && let Some(identifier) = subject.remove("identifier")
        && !is_supported_email_identity(&identifier)
    {
        return true;
    }

    // Reject identifier claims anywhere else in the credential
    contains_identifier(&remainder)
}

/// Returns the single proof from the canonical plain-JSON proof set.
pub(super) fn single_proof(value: &Value) -> Result<&Value> {
    let proofs = value
        .get("proof")
        .and_then(Value::as_array)
        .ok_or(BadgesManagerError::InvalidCredential)?;
    if proofs.len() != 1 || !proofs[0].is_object() {
        return Err(BadgesManagerError::InvalidCredential);
    }

    Ok(&proofs[0])
}

/// Returns whether a credential contains a portable identifier claim.
fn contains_identifier(value: &Value) -> bool {
    match value {
        Value::Array(values) => values.iter().any(contains_identifier),
        Value::Object(object) => {
            object.contains_key("identifier") || object.values().any(contains_identifier)
        }
        _ => false,
    }
}

/// Returns whether a subject identifier is exactly one OCG hashed email identity.
fn is_supported_email_identity(identifier: &Value) -> bool {
    // Require exactly one identity entry
    let Some([entry]) = identifier.as_array().map(Vec::as_slice) else {
        return false;
    };
    let Some(entry) = entry.as_object() else {
        return false;
    };

    // Require the exact salted hashed email identity shape
    entry.len() == 5
        && entry.get("type") == Some(&Value::from("IdentityObject"))
        && entry.get("hashed") == Some(&Value::from(true))
        && entry.get("identityType") == Some(&Value::from("emailAddress"))
        && entry
            .get("identityHash")
            .and_then(Value::as_str)
            .is_some_and(is_valid_identity_hash)
        && entry
            .get("salt")
            .and_then(Value::as_str)
            .is_some_and(|salt| !salt.is_empty())
}

/// Returns whether an identity hash is a `sha256$`-prefixed hex digest.
fn is_valid_identity_hash(hash: &str) -> bool {
    hash.strip_prefix("sha256$").is_some_and(|digest| {
        digest.len() == 64 && digest.bytes().all(|byte| byte.is_ascii_hexdigit())
    })
}

#[cfg(test)]
mod tests {
    use serde_json::{Value, json};

    use super::{contains_unsupported_identifier, recipient_display_name, single_proof};

    #[test]
    fn test_contains_unsupported_identifier_accepts_credential_without_identifier_claims() {
        let credential = json!({
            "credentialSubject": {"achievement": {"name": "Fixture Badge"}},
            "type": ["VerifiableCredential"]
        });
        assert!(!contains_unsupported_identifier(&credential));
    }

    #[test]
    fn test_contains_unsupported_identifier_accepts_single_hashed_email_identity() {
        let credential = json!({
            "credentialSubject": {
                "achievement": {"name": "Fixture Badge"},
                "identifier": [email_identity_entry()]
            }
        });
        assert!(!contains_unsupported_identifier(&credential));
    }

    #[test]
    fn test_contains_unsupported_identifier_detects_identifier_outside_subject_location() {
        for credential in [
            json!({"credentialSubject": {"results": [{"identifier": "recipient@example.test"}]}}),
            json!({"credentialSubject": {"achievement": {"identifier": "recipient@example.test"}}}),
            json!({"identifier": "recipient@example.test"}),
        ] {
            assert!(contains_unsupported_identifier(&credential));
        }
    }

    #[test]
    fn test_contains_unsupported_identifier_detects_malformed_subject_identity_shapes() {
        // Build every rejected variation of the supported subject identity
        let mut with_extra_key = email_identity_entry();
        with_extra_key["email"] = json!("recipient@example.test");
        let mut with_plaintext = email_identity_entry();
        with_plaintext["hashed"] = json!(false);
        let mut with_wrong_type = email_identity_entry();
        with_wrong_type["identityType"] = json!("url");
        let mut with_wrong_hash_prefix = email_identity_entry();
        with_wrong_hash_prefix["identityHash"] = json!(format!("md5${}", "a".repeat(64)));
        let mut with_short_digest = email_identity_entry();
        with_short_digest["identityHash"] = json!("sha256$abc");
        let mut with_nonhex_digest = email_identity_entry();
        with_nonhex_digest["identityHash"] = json!(format!("sha256${}", "z".repeat(64)));
        let mut with_empty_salt = email_identity_entry();
        with_empty_salt["salt"] = json!("");
        let mut without_salt = email_identity_entry();
        without_salt.as_object_mut().unwrap().remove("salt");
        let identifiers = [
            json!("recipient@example.test"),
            json!(email_identity_entry()),
            json!([]),
            json!([email_identity_entry(), email_identity_entry()]),
            json!([with_extra_key]),
            json!([with_plaintext]),
            json!([with_wrong_type]),
            json!([with_wrong_hash_prefix]),
            json!([with_short_digest]),
            json!([with_nonhex_digest]),
            json!([with_empty_salt]),
            json!([without_salt]),
        ];

        // Check every variation stays rejected
        for identifier in identifiers {
            let credential = json!({"credentialSubject": {"identifier": identifier}});
            assert!(contains_unsupported_identifier(&credential));
        }
    }

    #[test]
    fn test_recipient_display_name_falls_back_to_username() {
        // Resolve the public recipient label with and without a profile name
        let named = recipient_display_name(Some("Ada".to_string()), Some("ada".to_string()));
        let username_only = recipient_display_name(None, Some("ada".to_string()));

        // Check verification always has the available public identity label
        assert_eq!(named.as_deref(), Some("Ada"));
        assert_eq!(username_only.as_deref(), Some("ada"));
    }

    #[test]
    fn test_single_proof_accepts_one_object_in_array() {
        let credential = json!({"proof": [{"type": "DataIntegrityProof"}]});

        assert_eq!(
            single_proof(&credential).unwrap()["type"],
            "DataIntegrityProof"
        );
    }

    #[test]
    fn test_single_proof_rejects_noncanonical_shapes() {
        for credential in [
            json!({}),
            json!({"proof": {"type": "DataIntegrityProof"}}),
            json!({"proof": []}),
            json!({"proof": [{"type": "DataIntegrityProof"}, {"type": "DataIntegrityProof"}]}),
        ] {
            assert!(single_proof(&credential).is_err());
        }
    }

    // Helpers.

    /// Well-formed OCG-exported hashed email identity entry.
    fn email_identity_entry() -> Value {
        json!({
            "type": "IdentityObject",
            "hashed": true,
            "identityHash": format!("sha256${}", "a".repeat(64)),
            "identityType": "emailAddress",
            "salt": "0123456789abcdef0123456789abcdef"
        })
    }
}
