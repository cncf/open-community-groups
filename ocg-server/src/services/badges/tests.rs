//! Badge credential service tests.

use std::io::{Cursor, Read};

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use chrono::{TimeZone, Utc};
use flate2::read::GzDecoder;
use image::{DynamicImage, ImageFormat};
use serde_json::json;
use sha2::{Digest, Sha256};
use ssi_jwk::{Base64urlUInt, JWK, OctetParams, Params};
use ssi_verification_methods::ed25519_dalek::SigningKey;
use uuid::Uuid;

use crate::{
    config::{BadgeSigningKeyConfig, BadgeVerificationKeyConfig, BadgesConfig},
    types::badges::{
        BADGE_CRITERIA_MAX_CHARS, BADGE_DESCRIPTION_MAX_CHARS, BADGE_NAME_MAX_CHARS, BadgeSnapshot,
        BadgeSnapshotIssuer, UserBadge,
    },
};

use super::{
    BadgeService, BadgeServiceError, CredentialInput, contexts,
    png::{bake, extract},
    status::{STATUS_LIST_SIZE, STATUS_LIST_TTL_MS},
};

#[tokio::test]
async fn test_credential_profile_signs_and_verifies_after_key_rotation() {
    // Setup and issue the deterministic credential fixture
    let original_key = test_jwk(7);
    let original = service(original_key.clone(), vec![]);
    let award = sample_award();
    let created_at = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap();
    let credential = original
        .issue_credential(CredentialInput {
            award: &award,
            created_at,
        })
        .await
        .unwrap();
    let expected: serde_json::Value =
        serde_json::from_str(include_str!("testdata/opaque-subject-credential.json")).unwrap();

    // Check the exact Open Badges profile and privacy contract
    assert_eq!(credential, expected);
    let serialized = credential.to_string();
    for forbidden in ["identifier", "email", "hash", "salt", "contract-user"] {
        assert!(!serialized.contains(forbidden));
    }

    // Rotate the signing key while retaining the published public key
    let rotated = service(
        test_jwk(9),
        vec![BadgeVerificationKeyConfig {
            key_id: "test-key".to_string(),
            public_jwk: original_key.to_public(),
        }],
    );
    let verified = rotated.verify_credential(&credential).await.unwrap();
    assert_eq!(verified.user_badge_id, award.user_badge_id);
    assert_eq!(verified.status_list_id, award.badge_status_list_id);
    assert_eq!(verified.status_list_index, award.status_list_index);
}

#[tokio::test]
async fn test_credential_cache_reuses_immutable_signed_representation() {
    // Setup one immutable award and two distinct proof timestamps
    let service = service(test_jwk(7), vec![]);
    let award = sample_award();
    let first_created_at = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap();
    let later_created_at = Utc.with_ymd_and_hms(2024, 2, 4, 4, 5, 6).unwrap();

    // Request the same signed representation twice
    let first = service.cached_credential(&award, first_created_at).await.unwrap();
    let cached = service.cached_credential(&award, later_created_at).await.unwrap();

    // Check the second request reuses the first proof instead of signing again
    assert_eq!(cached, first);
    assert_eq!(cached["proof"]["created"], "2024-02-03T04:05:06.000Z");
}

#[tokio::test]
async fn test_maximum_badge_text_fits_png_credential_limit() {
    // Build a signed credential with worst-case escaped text at every input limit
    let service = service(test_jwk(7), vec![]);
    let mut award = sample_award();
    award.snapshot.criteria = "\u{0001}".repeat(BADGE_CRITERIA_MAX_CHARS);
    award.snapshot.description = "\u{0001}".repeat(BADGE_DESCRIPTION_MAX_CHARS);
    award.snapshot.name = "\u{0001}".repeat(BADGE_NAME_MAX_CHARS);
    let credential = service
        .issue_credential(CredentialInput {
            award: &award,
            created_at: Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
        })
        .await
        .unwrap();
    let credential = serde_json::to_vec(&credential).unwrap();

    // Check every valid persisted definition remains exportable
    assert!(credential.len() <= super::png::MAX_CREDENTIAL_SIZE);
    assert!(bake(&sample_png(), &credential).is_ok());
}

#[test]
fn test_png_baking_transcodes_replaces_and_validates_chunks() {
    // Bake and extract one credential from source artwork
    let source = sample_png();
    let first = bake(&source, br#"{"id":"first"}"#).unwrap();
    assert_eq!(extract(&first).unwrap(), br#"{"id":"first"}"#);

    // Baking always transcodes first, so an existing credential is replaced
    let replaced = bake(&first, br#"{"id":"second"}"#).unwrap();
    assert_eq!(extract(&replaced).unwrap(), br#"{"id":"second"}"#);

    // Reject corrupt, non-PNG, and unterminated input
    let mut corrupt = replaced;
    let last = corrupt.len() - 1;
    corrupt[last] ^= 1;
    assert!(matches!(
        extract(&corrupt),
        Err(BadgeServiceError::InvalidPng)
    ));
    assert!(matches!(
        extract(b"not a png"),
        Err(BadgeServiceError::InvalidPng)
    ));

    let mut truncated = first;
    truncated.truncate(truncated.len() - 12);
    assert!(matches!(
        extract(&truncated),
        Err(BadgeServiceError::InvalidPng)
    ));

    // Reject a terminated chunk stream that is not a decodable image
    let credential_chunk = test_png_chunk(*b"iTXt", b"openbadgecredential\0\0\0\0\0{}");
    let iend_chunk = test_png_chunk(*b"IEND", &[]);
    let fake = [
        b"\x89PNG\r\n\x1a\n".as_slice(),
        credential_chunk.as_slice(),
        iend_chunk.as_slice(),
    ]
    .concat();
    assert!(matches!(extract(&fake), Err(BadgeServiceError::InvalidPng)));
}

#[test]
fn test_reviewed_context_digests_match() {
    // Setup independently reviewed context digests
    let expected = [
        "3d34f4d4ef1bce691106e63798beb5e7b862ba841423f5ee1e53ab7ddf3bca84",
        "59955ced6697d61e03f2b2556febe5308ab16842846f5b586d7f1f7adec92734",
    ];

    // Calculate and compare every vendored context digest
    for ((_, context), expected) in contexts::reviewed_contexts().into_iter().zip(expected) {
        assert_eq!(hex::encode(Sha256::digest(context)), expected);
    }
}

#[tokio::test]
async fn test_status_list_cache_reuses_state_and_refreshes_revocations() {
    // Build one service and two distinct representation timestamps
    let service = service(test_jwk(7), vec![]);
    let list_id = Uuid::from_u128(31);
    let group_id = Uuid::from_u128(32);
    let first_created_at = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap();
    let changed_created_at = Utc.with_ymd_and_hms(2024, 2, 4, 4, 5, 6).unwrap();

    // Request unchanged state twice, then add a revocation to the same list
    let first = service
        .cached_status_list(list_id, group_id, &[], first_created_at)
        .await
        .unwrap();
    let cached = service
        .cached_status_list(list_id, group_id, &[], changed_created_at)
        .await
        .unwrap();
    let changed = service
        .cached_status_list(list_id, group_id, &[42], changed_created_at)
        .await
        .unwrap();

    // Check unchanged state reuses its proof while a revocation is signed immediately
    assert_eq!(cached, first);
    assert_eq!(cached["validFrom"], "2024-02-03T04:05:06.000Z");
    assert_eq!(changed["validFrom"], "2024-02-04T04:05:06.000Z");
    assert_eq!(decode_status_list(&changed)[42 / 8], 0b0010_0000);
}

#[tokio::test]
async fn test_status_list_uses_exact_size_orientation_and_ttl() {
    // Build a signed list with boundary and byte-orientation bits
    let service = service(test_jwk(7), vec![]);
    let list_id = Uuid::from_u128(31);
    let group_id = Uuid::from_u128(32);
    let status = service
        .issue_status_list(
            list_id,
            group_id,
            &[0, 7, 8, 131_071],
            Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
        )
        .await
        .unwrap();
    // Check the required TTL and exact uncompressed representation
    assert_eq!(status["credentialSubject"]["ttl"], STATUS_LIST_TTL_MS);
    let bytes = decode_status_list(&status);
    assert_eq!(bytes.len(), STATUS_LIST_SIZE);
    assert_eq!(bytes[0], 0b1000_0001);
    assert_eq!(bytes[1], 0b1000_0000);
    assert_eq!(bytes[STATUS_LIST_SIZE - 1], 0b0000_0001);

    // Check out-of-range persisted state fails closed
    assert!(matches!(
        service.issue_status_list(list_id, group_id, &[-1], Utc::now()).await,
        Err(BadgeServiceError::InvalidStatusList)
    ));
    assert!(matches!(
        service
            .issue_status_list(list_id, group_id, &[131_072], Utc::now())
            .await,
        Err(BadgeServiceError::InvalidStatusList)
    ));
}

#[tokio::test]
async fn test_unknown_context_fails_closed_during_signing() {
    // Attempt to sign a document that references an unreviewed context
    let service = service(test_jwk(7), vec![]);
    let result = service
        .sign_document(
            json!({
                "@context": [contexts::VC_CONTEXT_URL, "https://example.test/unknown-context"],
                "id": "https://example.test/document",
                "type": ["VerifiableCredential"],
                "issuer": "https://badges.example.test/badges/issuers/00000000-0000-0000-0000-000000000001",
                "credentialSubject": {"id": "urn:uuid:00000000-0000-0000-0000-000000000002"}
            }),
            Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
        )
        .await;

    // Check the closed loader rejects the operation
    assert!(matches!(result, Err(BadgeServiceError::SigningFailed)));
}

// Helpers.

/// Decode the generated multibase base64url gzip status bitstring.
fn decode_status_list(status: &serde_json::Value) -> Vec<u8> {
    let encoded = status["credentialSubject"]["encodedList"]
        .as_str()
        .unwrap()
        .strip_prefix('u')
        .unwrap();
    let compressed = URL_SAFE_NO_PAD.decode(encoded).unwrap();
    let mut decoder = GzDecoder::new(compressed.as_slice());
    let mut bytes = Vec::new();
    decoder.read_to_end(&mut bytes).unwrap();
    bytes
}

/// Build the deterministic active award used by credential tests.
fn sample_award() -> UserBadge {
    UserBadge {
        awarded_at: Utc.with_ymd_and_hms(2024, 1, 2, 3, 4, 5).unwrap(),
        badge_status_list_id: Uuid::from_u128(13),
        display_order: 0,
        group_id: Uuid::from_u128(12),
        is_listed: true,
        snapshot: BadgeSnapshot {
            criteria: "Complete the reviewed criteria".to_string(),
            description: "A deterministic badge fixture".to_string(),
            image_file_name: "credential-fixture.png".to_string(),
            issuer: BadgeSnapshotIssuer {
                community_id: Uuid::from_u128(11),
                community_name: "Fixture Community".to_string(),
                group_id: Uuid::from_u128(12),
                group_name: "Fixture Group".to_string(),
            },
            name: "Fixture Badge".to_string(),
        },
        status_list_index: 23,
        user_badge_id: Uuid::from_u128(14),

        badge_id: Some(Uuid::from_u128(15)),
        event_id: Some(Uuid::from_u128(16)),
        event_name: Some("Fixture Event".to_string()),
        recipient_name: Some("Credential Recipient".to_string()),
        recipient_username: Some("contract-user".to_string()),
        revocation_reason: None,
        revoked_at: None,
        revoked_by_user_id: None,
        user_id: Some(Uuid::from_u128(17)),
    }
}

/// Encode valid 512×512 PNG artwork.
fn sample_png() -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(512, 512)
        .write_to(&mut output, ImageFormat::Png)
        .unwrap();
    output.into_inner()
}

/// Build a badge service with one active key and retained public keys.
fn service(signing_jwk: JWK, verification_keys: Vec<BadgeVerificationKeyConfig>) -> BadgeService {
    BadgeService::new(
        "https://badges.example.test",
        &BadgesConfig {
            signing_key: BadgeSigningKeyConfig {
                key_id: if signing_jwk.to_public() == test_jwk(7).to_public() {
                    "test-key".to_string()
                } else {
                    "rotated-key".to_string()
                },
                private_jwk: signing_jwk,
            },
            verification_keys,
        },
    )
}

/// Build deterministic Ed25519 JWK material from a repeated seed byte.
fn test_jwk(seed: u8) -> JWK {
    let signing_key = SigningKey::from_bytes(&[seed; 32]);
    JWK::from(Params::OKP(OctetParams {
        curve: "Ed25519".to_string(),
        public_key: Base64urlUInt(signing_key.verifying_key().to_bytes().to_vec()),
        private_key: Some(Base64urlUInt(signing_key.to_bytes().to_vec())),
    }))
}

/// Encode one PNG chunk with a valid CRC for malformed-stream tests.
fn test_png_chunk(kind: [u8; 4], data: &[u8]) -> Vec<u8> {
    let mut chunk = Vec::with_capacity(data.len() + 12);
    chunk.extend_from_slice(&u32::try_from(data.len()).unwrap().to_be_bytes());
    chunk.extend_from_slice(&kind);
    chunk.extend_from_slice(data);
    let mut hasher = crc32fast::Hasher::new();
    hasher.update(&kind);
    hasher.update(data);
    chunk.extend_from_slice(&hasher.finalize().to_be_bytes());
    chunk
}
