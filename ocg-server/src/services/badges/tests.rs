//! Badge credential manager tests.

use std::io::Cursor;

use chrono::{TimeZone, Utc};
use image::{DynamicImage, ImageFormat};
use serde_json::json;
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
    BadgesManager, BadgesManagerError, CredentialInput, contexts, png::bake,
    status::STATUS_LIST_TTL_MS,
};

#[tokio::test(start_paused = true)]
async fn test_cached_credential_rejects_cold_request_when_signer_is_busy() {
    // Setup a manager whose cold-signing guard is already held
    let manager = manager(test_jwk(7), vec![]);
    let _guard = manager.credential_cache.signing_guard().await.unwrap();

    // Run one cold request against the busy signer
    let result = manager
        .cached_credential(
            &sample_award(),
            Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
        )
        .await;

    // Check the bounded wait fails closed instead of queuing indefinitely
    assert!(matches!(result, Err(BadgesManagerError::Busy)));
}

#[tokio::test]
async fn test_credential_cache_reuses_immutable_signed_representation() {
    // Setup one immutable award and two distinct proof timestamps
    let manager = manager(test_jwk(7), vec![]);
    let award = sample_award();
    let first_created_at = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap();
    let later_created_at = Utc.with_ymd_and_hms(2024, 2, 4, 4, 5, 6).unwrap();

    // Request the same signed representation twice
    let first = manager.cached_credential(&award, first_created_at).await.unwrap();
    let cached = manager.cached_credential(&award, later_created_at).await.unwrap();

    // Check the second request reuses the first proof instead of signing again
    assert_eq!(cached, first);
    assert_eq!(cached["proof"]["created"], "2024-02-03T04:05:06.000Z");
}

#[tokio::test]
async fn test_credential_profile_signs_and_verifies_after_key_rotation() {
    // Setup and issue the deterministic credential fixture
    let original_key = test_jwk(7);
    let original = manager(original_key.clone(), vec![]);
    let credential = signed_credential(&original).await;
    let expected: serde_json::Value =
        serde_json::from_str(include_str!("testdata/opaque-subject-credential.json")).unwrap();

    // Check the exact Open Badges profile and privacy contract
    assert_eq!(credential, expected);
    let serialized = credential.to_string();
    for forbidden in ["identifier", "email", "hash", "salt", "contract-user"] {
        assert!(!serialized.contains(forbidden));
    }

    // Rotate the signing key while retaining the published public key
    let rotated = manager(
        test_jwk(9),
        vec![BadgeVerificationKeyConfig {
            key_id: "test-key".to_string(),
            public_jwk: original_key.to_public(),
        }],
    );
    let award = sample_award();
    let verified = rotated.verify_credential(&credential).await.unwrap();
    assert_eq!(verified.status_list_id, award.badge_status_list_id);
    assert_eq!(verified.status_list_index, award.status_list_index);
    assert_eq!(verified.user_badge_id, award.user_badge_id);
    assert_eq!(verified.valid_from, award.awarded_at);
}

#[tokio::test]
async fn test_maximum_badge_text_fits_png_credential_limit() {
    // Build a signed credential with worst-case escaped text at every input limit
    let manager = manager(test_jwk(7), vec![]);
    let mut award = sample_award();
    award.snapshot.criteria = "\u{0001}".repeat(BADGE_CRITERIA_MAX_CHARS);
    award.snapshot.description = "\u{0001}".repeat(BADGE_DESCRIPTION_MAX_CHARS);
    award.snapshot.name = "\u{0001}".repeat(BADGE_NAME_MAX_CHARS);
    let credential = manager
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

#[tokio::test]
async fn test_status_list_cache_reuses_state_and_refreshes_revocations() {
    // Build one manager and two distinct representation timestamps
    let manager = manager(test_jwk(7), vec![]);
    let list_id = Uuid::from_u128(31);
    let group_id = Uuid::from_u128(32);
    let first_created_at = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap();
    let changed_created_at = Utc.with_ymd_and_hms(2024, 2, 4, 4, 5, 6).unwrap();

    // Request unchanged state twice, then add a revocation to the same list
    let first = manager
        .cached_status_list(list_id, group_id, &[], first_created_at)
        .await
        .unwrap();
    let cached = manager
        .cached_status_list(list_id, group_id, &[], changed_created_at)
        .await
        .unwrap();
    let changed = manager
        .cached_status_list(list_id, group_id, &[42], changed_created_at)
        .await
        .unwrap();

    // Check unchanged state reuses its proof while a revocation is signed immediately
    assert_eq!(cached, first);
    assert_eq!(cached["validFrom"], "2024-02-03T04:05:06.000Z");
    assert_eq!(changed["validFrom"], "2024-02-04T04:05:06.000Z");
    assert_ne!(
        changed["credentialSubject"]["encodedList"],
        first["credentialSubject"]["encodedList"]
    );
}

#[tokio::test]
async fn test_status_list_profile_uses_required_ttl_and_revocation_purpose() {
    // Issue one signed status list for a known group
    let manager = manager(test_jwk(7), vec![]);
    let list_id = Uuid::from_u128(31);
    let group_id = Uuid::from_u128(32);
    let status = manager
        .issue_status_list(
            list_id,
            group_id,
            &[42],
            Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
        )
        .await
        .unwrap();

    // Check the published revocation-only document profile
    let status_list_url = format!("https://badges.example.test/badges/status-lists/{list_id}");
    assert_eq!(status["@context"], json!([contexts::VC_CONTEXT_URL]));
    assert_eq!(status["id"], status_list_url);
    assert_eq!(
        status["type"],
        json!(["VerifiableCredential", "BitstringStatusListCredential"])
    );
    assert_eq!(
        status["issuer"],
        format!("https://badges.example.test/badges/issuers/{group_id}")
    );
    assert_eq!(status["validFrom"], "2024-02-03T04:05:06.000Z");
    assert_eq!(
        status["credentialSubject"]["id"],
        format!("{status_list_url}#list")
    );
    assert_eq!(status["credentialSubject"]["type"], "BitstringStatusList");
    assert_eq!(status["credentialSubject"]["statusPurpose"], "revocation");
    assert_eq!(status["credentialSubject"]["ttl"], STATUS_LIST_TTL_MS);
    assert!(
        status["credentialSubject"]["encodedList"]
            .as_str()
            .unwrap()
            .starts_with('u')
    );
}

#[tokio::test]
async fn test_unknown_context_fails_closed_during_signing() {
    // Attempt to sign a document that references an unreviewed context
    let manager = manager(test_jwk(7), vec![]);
    let result = manager
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
    assert!(matches!(result, Err(BadgesManagerError::SigningFailed)));
}

#[tokio::test]
async fn test_verify_credential_rejects_foreign_and_malformed_urls() {
    // Issue the valid signed fixture
    let manager = manager(test_jwk(7), vec![]);
    let credential = signed_credential(&manager).await;

    // Check foreign, nested, and malformed credential identifiers are rejected
    for id in [
        "https://attacker.example.test/badges/credentials/00000000-0000-0000-0000-00000000000e",
        "https://badges.example.test/badges/credentials/extra/00000000-0000-0000-0000-00000000000e",
        "https://badges.example.test/badges/credentials/not-a-uuid",
    ] {
        let mut altered = credential.clone();
        altered["id"] = json!(id);
        assert!(matches!(
            manager.verify_credential(&altered).await,
            Err(BadgesManagerError::InvalidUrl)
        ));
    }

    // Check a foreign issuer URL is rejected before proof verification
    let mut foreign_issuer = credential;
    foreign_issuer["issuer"] =
        json!("https://attacker.example.test/badges/issuers/00000000-0000-0000-0000-00000000000c");
    assert!(matches!(
        manager.verify_credential(&foreign_issuer).await,
        Err(BadgesManagerError::InvalidUrl)
    ));
}

#[tokio::test]
async fn test_verify_credential_rejects_invalid_status_entries() {
    // Setup the manager and the valid signed status entry
    let manager = manager(test_jwk(7), vec![]);
    let created_at = Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap();
    let valid_status = credential_status();

    // Check every unsupported signed status entry field is rejected
    let rejected_entries = [
        (
            "id",
            json!(
                "https://badges.example.test/badges/credentials/00000000-0000-0000-0000-00000000000e#other"
            ),
        ),
        ("statusListIndex", json!("2a")),
        ("statusListIndex", json!("023")),
        ("statusListIndex", json!("131072")),
        ("statusPurpose", json!("suspension")),
    ];
    for (field, value) in rejected_entries {
        let mut status = valid_status.clone();
        status[field] = value;
        let credential = manager
            .sign_document(credential_document(&status), created_at)
            .await
            .unwrap();
        assert!(matches!(
            manager.verify_credential(&credential).await,
            Err(BadgesManagerError::InvalidStatusList)
        ));
    }

    // Check a signed foreign status-list reference is rejected
    let mut status = valid_status;
    status["statusListCredential"] = json!(
        "https://attacker.example.test/badges/status-lists/00000000-0000-0000-0000-00000000000d"
    );
    let credential = manager
        .sign_document(credential_document(&status), created_at)
        .await
        .unwrap();
    assert!(matches!(
        manager.verify_credential(&credential).await,
        Err(BadgesManagerError::InvalidUrl)
    ));
}

#[tokio::test]
async fn test_verify_credential_rejects_invalid_valid_from() {
    // Sign a credential whose award timestamp is not RFC 3339
    let manager = manager(test_jwk(7), vec![]);
    let mut document = credential_document(&credential_status());
    document["validFrom"] = json!("not-a-timestamp");
    let credential = manager
        .sign_document(document, Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap())
        .await
        .unwrap();

    // Check a correctly signed malformed timestamp remains an invalid credential
    assert!(matches!(
        manager.verify_credential(&credential).await,
        Err(BadgesManagerError::InvalidCredential)
    ));
}

#[tokio::test]
async fn test_verify_credential_rejects_tampered_content() {
    // Issue the valid signed fixture
    let manager = manager(test_jwk(7), vec![]);
    let mut credential = signed_credential(&manager).await;

    // Alter one signed claim without re-signing
    credential["credentialSubject"]["achievement"]["name"] = json!("Escalated Badge");

    // Check proof verification rejects the modification
    assert!(matches!(
        manager.verify_credential(&credential).await,
        Err(BadgesManagerError::InvalidProof)
    ));
}

#[tokio::test]
async fn test_verify_credential_rejects_unknown_verification_method() {
    // Issue a credential signed by a key outside the verifier allowlist
    let signer = manager(test_jwk(9), vec![]);
    let verifier = manager(test_jwk(7), vec![]);
    let unknown_key = signed_credential(&signer).await;

    // Check the closed allowlist rejects the unknown proof key
    assert!(matches!(
        verifier.verify_credential(&unknown_key).await,
        Err(BadgesManagerError::UnknownVerificationMethod)
    ));

    // Check a proof key outside the local key namespace is rejected
    let mut foreign_method = signed_credential(&verifier).await;
    foreign_method["proof"]["verificationMethod"] =
        json!("https://attacker.example.test/badges/keys/test-key");
    assert!(matches!(
        verifier.verify_credential(&foreign_method).await,
        Err(BadgesManagerError::UnknownVerificationMethod)
    ));
}

#[tokio::test]
async fn test_verify_credential_rejects_unsupported_profile_and_identifier_claims() {
    // Issue the valid signed fixture
    let manager = manager(test_jwk(7), vec![]);
    let credential = signed_credential(&manager).await;

    // Check a credential without the Open Badges context is rejected
    let mut wrong_context = credential.clone();
    wrong_context["@context"] = json!([contexts::VC_CONTEXT_URL]);
    assert!(matches!(
        manager.verify_credential(&wrong_context).await,
        Err(BadgesManagerError::InvalidCredential)
    ));

    // Check an unexpected credential type is rejected
    let mut wrong_type = credential.clone();
    wrong_type["type"] = json!(["VerifiableCredential"]);
    assert!(matches!(
        manager.verify_credential(&wrong_type).await,
        Err(BadgesManagerError::InvalidCredential)
    ));

    // Check a nested portable identifier claim is rejected
    let mut with_identifier = credential.clone();
    with_identifier["credentialSubject"]["identifier"] = json!("recipient@example.test");
    assert!(matches!(
        manager.verify_credential(&with_identifier).await,
        Err(BadgesManagerError::InvalidCredential)
    ));

    // Check a subject that does not match the credential identifier is rejected
    let mut mismatched_subject = credential;
    mismatched_subject["credentialSubject"]["id"] =
        json!(format!("urn:uuid:{}", Uuid::from_u128(99)));
    assert!(matches!(
        manager.verify_credential(&mismatched_subject).await,
        Err(BadgesManagerError::InvalidCredential)
    ));
}

#[tokio::test]
async fn test_verify_credential_rejects_unsupported_proof_profile() {
    // Issue the valid signed fixture
    let manager = manager(test_jwk(7), vec![]);
    let credential = signed_credential(&manager).await;

    // Check every unsupported fixed proof field is rejected
    for (field, value) in [
        ("cryptosuite", json!("ecdsa-rdfc-2019")),
        ("proofPurpose", json!("authentication")),
        ("type", json!("Ed25519Signature2020")),
    ] {
        let mut altered = credential.clone();
        altered["proof"][field] = value;
        assert!(matches!(
            manager.verify_credential(&altered).await,
            Err(BadgesManagerError::InvalidProof)
        ));
    }

    // Check a missing proof is rejected
    let mut missing_proof = credential.clone();
    missing_proof.as_object_mut().unwrap().remove("proof");
    assert!(matches!(
        manager.verify_credential(&missing_proof).await,
        Err(BadgesManagerError::InvalidCredential)
    ));

    // Check duplicated proofs are rejected
    let mut duplicated_proofs = credential.clone();
    let proof = duplicated_proofs["proof"].clone();
    duplicated_proofs["proof"] = json!([proof.clone(), proof]);
    assert!(matches!(
        manager.verify_credential(&duplicated_proofs).await,
        Err(BadgesManagerError::InvalidCredential)
    ));
}

// Helpers.

/// Build an unsigned opaque-subject credential with one custom status entry.
fn credential_document(credential_status: &serde_json::Value) -> serde_json::Value {
    let credential_url =
        "https://badges.example.test/badges/credentials/00000000-0000-0000-0000-00000000000e";
    json!({
        "@context": [contexts::VC_CONTEXT_URL, contexts::OPEN_BADGES_CONTEXT_URL],
        "id": credential_url,
        "type": ["VerifiableCredential", "OpenBadgeCredential"],
        "issuer": "https://badges.example.test/badges/issuers/00000000-0000-0000-0000-00000000000c",
        "validFrom": "2024-01-02T03:04:05.000Z",
        "name": "Fixture Badge",
        "credentialSubject": {
            "id": "urn:uuid:00000000-0000-0000-0000-00000000000e",
            "type": ["AchievementSubject"],
            "achievement": {
                "id": format!("{credential_url}#achievement"),
                "type": ["Achievement"],
                "criteria": {"narrative": "Complete the reviewed criteria"},
                "description": "A deterministic badge fixture",
                "name": "Fixture Badge"
            }
        },
        "credentialStatus": credential_status
    })
}

/// Builds the valid credential status entry used by verification tests.
fn credential_status() -> serde_json::Value {
    json!({
        "id": "https://badges.example.test/badges/credentials/00000000-0000-0000-0000-00000000000e#status",
        "type": "BitstringStatusListEntry",
        "statusPurpose": "revocation",
        "statusListIndex": "23",
        "statusListCredential": "https://badges.example.test/badges/status-lists/00000000-0000-0000-0000-00000000000d"
    })
}

/// Build a badges manager with one active key and retained public keys.
fn manager(signing_jwk: JWK, verification_keys: Vec<BadgeVerificationKeyConfig>) -> BadgesManager {
    BadgesManager::new(
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

/// Issue the deterministic signed credential fixture.
async fn signed_credential(manager: &BadgesManager) -> serde_json::Value {
    manager
        .issue_credential(CredentialInput {
            award: &sample_award(),
            created_at: Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
        })
        .await
        .unwrap()
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
