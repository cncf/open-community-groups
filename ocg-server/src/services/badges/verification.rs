//! OCG badge credential proof and profile verification.

use serde_json::Value;
use uuid::Uuid;

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
    pub valid_from: String,
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

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::contains_identifier;

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
}
