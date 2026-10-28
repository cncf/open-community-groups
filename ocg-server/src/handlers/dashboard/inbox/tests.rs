use std::collections::HashMap;

use uuid::Uuid;

use super::requested_conversation_id;

#[test]
fn test_requested_conversation_id() {
    let inbox_conversation_id = Uuid::new_v4();
    let cases = [
        ("missing parameter", None, None),
        ("malformed id", Some("invalid".to_string()), None),
        (
            "valid id",
            Some(inbox_conversation_id.to_string()),
            Some(inbox_conversation_id),
        ),
    ];

    for (label, value, expected) in cases {
        let query: HashMap<String, String> = value
            .map(|value| ("conversation_id".to_string(), value))
            .into_iter()
            .collect();

        assert_eq!(requested_conversation_id(&query), expected, "case {label}");
    }
}
