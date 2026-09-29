use std::collections::HashMap;

use uuid::Uuid;

use super::requested_conversation_id;

#[test]
fn test_requested_conversation_id_ignores_malformed_id() {
    let query = HashMap::from([("conversation_id".to_string(), "invalid".to_string())]);

    assert_eq!(requested_conversation_id(&query), None);
}

#[test]
fn test_requested_conversation_id_returns_none_without_parameter() {
    assert_eq!(requested_conversation_id(&HashMap::new()), None);
}

#[test]
fn test_requested_conversation_id_returns_valid_id() {
    let inbox_conversation_id = Uuid::new_v4();
    let query = HashMap::from([(
        "conversation_id".to_string(),
        inbox_conversation_id.to_string(),
    )]);

    assert_eq!(
        requested_conversation_id(&query),
        Some(inbox_conversation_id)
    );
}
