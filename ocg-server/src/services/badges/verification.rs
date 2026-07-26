//! OCG badge credential proof and profile verification.

use chrono::{DateTime, Utc};
use serde_json::Value;
use uuid::Uuid;

use super::{BadgesManagerError, Result};

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
}

/// Returns whether an uploaded credential contains a portable identifier claim.
pub(super) fn contains_identifier(value: &Value) -> bool {
    match value {
        Value::Array(values) => values.iter().any(contains_identifier),
        Value::Object(object) => {
            object.contains_key("identifier") || object.values().any(contains_identifier)
        }
        _ => false,
    }
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

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{contains_identifier, single_proof};

    #[test]
    fn test_contains_identifier_accepts_credential_without_identifier_claims() {
        let credential = json!({
            "credentialSubject": {"achievement": {"name": "Fixture Badge"}},
            "type": ["VerifiableCredential"]
        });
        assert!(!contains_identifier(&credential));
    }

    #[test]
    fn test_contains_identifier_detects_identifier_inside_nested_array() {
        let credential = json!({
            "credentialSubject": {"results": [{"identifier": "recipient@example.test"}]}
        });
        assert!(contains_identifier(&credential));
    }

    #[test]
    fn test_contains_identifier_detects_identifier_inside_nested_object() {
        let credential = json!({
            "credentialSubject": {"achievement": {"identifier": "recipient@example.test"}}
        });
        assert!(contains_identifier(&credential));
    }

    #[test]
    fn test_contains_identifier_detects_top_level_identifier() {
        assert!(contains_identifier(
            &json!({"identifier": "recipient@example.test"})
        ));
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
}
