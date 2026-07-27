//! Status-list encoding and cache tests.

use std::io::Read;

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use flate2::read::GzDecoder;
use serde_json::json;
use uuid::Uuid;

use super::{
    BadgesManagerError, STATUS_LIST_ENTRIES, STATUS_LIST_SIZE, StatusListCache, encode_status_list,
};

#[test]
fn test_encode_status_list_encodes_empty_state_as_zero_bits() {
    // Encode a list without revocations
    let encoded = encode_status_list(&[]).unwrap();

    // Check the exact all-zero uncompressed representation
    let bytes = decode_status_list(&encoded);
    assert_eq!(bytes.len(), STATUS_LIST_SIZE);
    assert!(bytes.iter().all(|byte| *byte == 0));
}

#[test]
fn test_encode_status_list_rejects_out_of_range_indexes() {
    // Check persisted state outside the published range fails closed
    assert!(matches!(
        encode_status_list(&[-1]),
        Err(BadgesManagerError::InvalidStatusList)
    ));
    assert!(matches!(
        encode_status_list(&[i32::try_from(STATUS_LIST_ENTRIES).unwrap()]),
        Err(BadgesManagerError::InvalidStatusList)
    ));
}

#[test]
fn test_encode_status_list_uses_exact_size_and_msb_orientation() {
    // Encode boundary and byte-orientation bits
    let encoded = encode_status_list(&[0, 7, 8, 131_071]).unwrap();

    // Check the multibase prefix and exact uncompressed representation
    assert!(encoded.starts_with('u'));
    let bytes = decode_status_list(&encoded);
    assert_eq!(bytes.len(), STATUS_LIST_SIZE);
    assert_eq!(bytes[0], 0b1000_0001);
    assert_eq!(bytes[1], 0b1000_0000);
    assert_eq!(bytes[STATUS_LIST_SIZE - 1], 0b0000_0001);
}

#[tokio::test]
async fn test_status_list_cache_serves_only_exact_group_and_state() {
    // Setup one cached representation for a known group and state
    let cache = StatusListCache::new();
    let list_id = Uuid::from_u128(41);
    let group_id = Uuid::from_u128(42);
    let credential = json!({"id": "cached-status-list"});
    cache.insert(list_id, credential.clone(), group_id, &[7]).await;

    // Check only the exact current list, group, and revocation state is served
    assert_eq!(cache.get(list_id, group_id, &[7]).await, Some(credential));
    assert_eq!(cache.get(list_id, Uuid::from_u128(43), &[7]).await, None);
    assert_eq!(cache.get(list_id, group_id, &[7, 9]).await, None);
    assert_eq!(cache.get(Uuid::from_u128(44), group_id, &[7]).await, None);
}

// Helpers.

/// Decode one multibase base64url gzip status bitstring.
fn decode_status_list(encoded: &str) -> Vec<u8> {
    let encoded = encoded.strip_prefix('u').unwrap();
    let compressed = URL_SAFE_NO_PAD.decode(encoded).unwrap();
    let mut decoder = GzDecoder::new(compressed.as_slice());
    let mut bytes = Vec::new();
    decoder.read_to_end(&mut bytes).unwrap();
    bytes
}
