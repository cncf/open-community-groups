use std::io::Cursor;

use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderMap, HeaderValue, Request, StatusCode,
        header::{ACCEPT, CACHE_CONTROL, CONTENT_TYPE},
    },
};
use chrono::{TimeZone, Utc};
use image::{DynamicImage, ImageFormat};
use serde_json::{Value, json};
use ssi_jwk::JWK;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::{BadgeSigningKeyConfig, BadgesConfig, HttpServerConfig},
    db::mock::MockDB,
    handlers::tests::{TestRouterBuilder, sample_site_settings},
    router::CACHE_CONTROL_PUBLIC_SHARED,
    services::{
        badges::{CredentialInput, EmailIdentity},
        notifications::MockNotificationsManager,
    },
    types::badges::{
        BadgeSnapshot, BadgeSnapshotIssuer, BadgeStatusList, PublicBadgeSnapshot,
        PublicBadgeSnapshotIssuer, PublicUserBadge, UserBadge,
    },
};

use super::*;

#[test]
fn test_accepts_credential_requires_the_supported_media_type() {
    // Build supported, ordinary, parameterized, and explicitly rejected headers
    let mut credential_headers = HeaderMap::new();
    credential_headers.insert(
        ACCEPT,
        HeaderValue::from_static("text/html, application/vc+ld+json"),
    );
    let mut html_headers = HeaderMap::new();
    html_headers.insert(ACCEPT, HeaderValue::from_static("text/html"));
    let mut parameterized_headers = HeaderMap::new();
    parameterized_headers.insert(
        ACCEPT,
        HeaderValue::from_static("application/vc+ld+json; charset=utf-8"),
    );
    let mut rejected_headers = HeaderMap::new();
    rejected_headers.insert(
        ACCEPT,
        HeaderValue::from_static("application/vc+ld+json; q=0, application/vc+ld+json; q=invalid"),
    );

    // Check representation selection remains explicit
    assert!(accepts_credential(&credential_headers));
    assert!(!accepts_credential(&html_headers));
    assert!(accepts_credential(&parameterized_headers));
    assert!(!accepts_credential(&rejected_headers));
}

#[tokio::test]
async fn test_credential_html_response_uses_public_snapshot_and_cache_contract() {
    // Setup a public award and site settings
    let award = sample_user_badge();
    let user_badge_id = award.user_badge_id;
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .return_once(move |_| Ok(Some(award)));
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request the browser representation
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/credentials/{user_badge_id}"))
                .header(ACCEPT, "text/html")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check the page and representation-sensitive cache headers
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers.get("vary").unwrap(), CREDENTIAL_CACHE_VARY);
    assert!(parts.headers.get("cache-control").is_some());
    assert!(String::from_utf8_lossy(&body).contains("Test Badge"));
}

#[tokio::test]
async fn test_credential_json_ld_response_is_signed_and_shared_cached() {
    // Setup a public award and active signing configuration
    let award = sample_user_badge();
    let user_badge_id = award.user_badge_id;
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .return_once(move |_| Ok(Some(award)));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the signed credential representation explicitly
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/credentials/{user_badge_id}"))
                .header(ACCEPT, "application/vc+ld+json")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the signed JSON-LD and bounded shared-cache boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "application/vc+ld+json"
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_PUBLIC_SHARED
    );
    assert_eq!(parts.headers.get("vary").unwrap(), CREDENTIAL_CACHE_VARY);
    assert_eq!(
        body["id"],
        format!("https://badges.example.test/badges/credentials/{user_badge_id}")
    );
    assert_eq!(body["issuer"]["name"], "Test Group");
    assert_eq!(body["issuer"]["type"], json!(["Profile"]));
    assert_eq!(body["proof"].as_array().unwrap().len(), 1);
    assert_eq!(body["proof"][0]["cryptosuite"], "eddsa-rdfc-2022");
    assert!(!body.to_string().contains("identifier"));
}

#[tokio::test]
async fn test_credential_unknown_award_returns_not_found() {
    // Setup an unknown public award
    let user_badge_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .return_once(|_| Ok(None));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request the missing credential
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/credentials/{user_badge_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check unknown opaque identifiers stay private
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_issuer_key_returns_immutable_multikey_document() {
    // Setup a public router with one active signing method
    let group_id = Uuid::new_v4();
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Resolve the published key from the issuer profile
    let response = router
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/badges/issuers/{group_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let profile: Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let key_multibase = profile["verificationMethod"][0]["publicKeyMultibase"]
        .as_str()
        .unwrap()
        .to_string();

    // Request the dereferenceable standalone key document
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/issuers/{group_id}/keys/{key_multibase}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the immutable content-addressed Multikey document
    assert_eq!(parts.status, StatusCode::OK);
    let issuer_id = format!("https://badges.example.test/badges/issuers/{group_id}");
    assert_eq!(body["@context"], "https://w3id.org/security/multikey/v1");
    assert_eq!(body["id"], format!("{issuer_id}/keys/{key_multibase}"));
    assert_eq!(body["type"], "Multikey");
    assert_eq!(body["controller"], issuer_id);
    assert_eq!(body["publicKeyMultibase"], key_multibase);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        "public, max-age=31536000, immutable"
    );
}

#[tokio::test]
async fn test_issuer_key_unknown_multibase_returns_not_found() {
    // Setup a public router with one active signing method
    let group_id = Uuid::new_v4();
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request a key document outside the retained allowlist
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/issuers/{group_id}/keys/z6MkUnknown"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check unknown keys are not published
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_issuer_returns_stable_public_profile() {
    // Setup a public router with one active signing method
    let group_id = Uuid::new_v4();
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the issuer profile
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/issuers/{group_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check stable issuer identity and public caching
    assert_eq!(parts.status, StatusCode::OK);
    let issuer_id = format!("https://badges.example.test/badges/issuers/{group_id}");
    let method = &body["verificationMethod"][0];
    assert_eq!(
        body["@context"],
        json!([
            "https://www.w3.org/ns/cid/v1",
            "https://purl.imsglobal.org/spec/ob/v3p0/context-3.0.3.json"
        ])
    );
    assert_eq!(body["id"], issuer_id);
    assert_eq!(body["type"], json!(["Profile"]));
    assert_eq!(body["assertionMethod"][0], method["id"]);
    assert_eq!(body["verificationMethod"].as_array().unwrap().len(), 1);
    assert_eq!(method["controller"], issuer_id);
    assert_eq!(method["type"], "Multikey");
    assert_eq!(
        method["id"],
        format!(
            "{issuer_id}/keys/{}",
            method["publicKeyMultibase"].as_str().unwrap()
        )
    );
    assert!(method["publicKeyMultibase"].as_str().unwrap().starts_with("z6Mk"));
    assert!(parts.headers.get("cache-control").is_some());
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

#[tokio::test]
async fn test_status_list_returns_signed_current_state() {
    // Setup one current status list and active signing configuration
    let status = sample_badge_status_list();
    let status_list_id = status.badge_status_list_id;
    let mut db = MockDB::new();
    db.expect_get_badge_status_list()
        .times(1)
        .withf(move |id| *id == status_list_id)
        .return_once(move |_| Ok(Some(status)));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the signed status-list credential
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/status-lists/{status_list_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the signed status response and bounded public cache policy
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "application/vc+ld+json"
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        STATUS_LIST_CACHE_CONTROL
    );
    assert_eq!(body["credentialSubject"]["statusPurpose"], "revocation");
    assert!(body["issuer"].get("type").is_none());
    assert_eq!(body["proof"].as_array().unwrap().len(), 1);
    assert_eq!(body["proof"][0]["cryptosuite"], "eddsa-rdfc-2022");
}

#[tokio::test]
async fn test_status_list_unknown_id_returns_not_found() {
    // Setup an unknown status list
    let status_list_id = Uuid::new_v4();
    let mut db = MockDB::new();
    db.expect_get_badge_status_list()
        .times(1)
        .withf(move |id| *id == status_list_id)
        .return_once(|_| Ok(None));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request the missing status list
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/badges/status-lists/{status_list_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check missing lists are not synthesized
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_user_profile_badges_returns_public_projection() {
    // Setup one discoverable public badge
    let award = sample_user_badge();
    let expected = vec![PublicUserBadge {
        snapshot: PublicBadgeSnapshot {
            image_file_name: award.snapshot.image_file_name,
            issuer: PublicBadgeSnapshotIssuer {
                community_name: award.snapshot.issuer.community_name,
                group_name: award.snapshot.issuer.group_name,
            },
            name: award.snapshot.name,
        },
        user_badge_id: award.user_badge_id,
    }];
    let output = expected.clone();
    let mut db = MockDB::new();
    db.expect_list_user_public_badges()
        .times(1)
        .withf(move |limit, offset, username| *limit == 50 && *offset == 0 && username == "ada")
        .return_once(move |_, _, _| Ok(output));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request the public profile projection
    let response = router
        .oneshot(
            Request::builder()
                .uri("/users/ada/badges")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: Vec<PublicUserBadge> =
        serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check only the bounded public DTO crosses the shared-cache boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert!(parts.headers.get(CACHE_CONTROL).is_some());
    assert_eq!(body, expected);
}

#[tokio::test]
async fn test_user_profile_badges_rejects_page_above_public_cap() {
    // Build a public router whose database must not be queried for invalid pagination
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
        .build()
        .await;

    // Request a page larger than the fixed public response cap
    let response = router
        .oneshot(
            Request::builder()
                .uri("/users/ada/badges?limit=51")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check validation rejects the request before any public-profile reads
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_verify_page_is_never_cached() {
    // Setup site settings for the verification form
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request the local verification form
    let response = router
        .oneshot(Request::builder().uri("/badges/verify").body(Body::empty()).unwrap())
        .await
        .unwrap();

    // Check sensitive verification output cannot be cached
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers().get("cache-control").unwrap(), "no-store");
}

#[tokio::test]
async fn test_verify_post_flags_stale_email_bound_award_as_superseded() {
    // Issue and bake one export credential bound to a superseded identity
    let mut award = sample_user_badge();
    award.identity_bound_at = Some(Utc.with_ymd_and_hms(2024, 3, 4, 5, 6, 7).unwrap());
    award.identity_hash =
        Some("1f5c1b4c4459c1197a51122a1e86154bbd1eec1c4bb9e34c7c9e4c4e5f3b2a10".to_string());
    award.identity_salt = Some("fedcba9876543210fedcba9876543210".to_string());
    let user_badge_id = award.user_badge_id;
    let server_cfg = badges_server_config();
    let badges_manager =
        BadgesManager::new(&server_cfg.base_url, server_cfg.badges.as_ref().unwrap());
    let credential = badges_manager
        .issue_credential(CredentialInput {
            award: &award,
            created_at: Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
            email_identity: Some(EmailIdentity {
                hash: "fa4e696fed1caae3ce9bda21a14b5d7960f8ef36bf1566164dafb09f4c8ac324"
                    .to_string(),
                salt: "0123456789abcdef0123456789abcdef".to_string(),
            }),
        })
        .await
        .unwrap();
    let credential = serde_json::to_vec(&credential).unwrap();
    let png = png::bake(&sample_png(), &credential).unwrap();

    // Setup the rebound durable award and verification page settings
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .returning(move |_| Ok(Some(award.clone())));
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_server_cfg(server_cfg)
        .build()
        .await;
    let boundary = "BADGE-PNG-VERIFY-BOUNDARY";

    // Submit the stale exported PNG as multipart form data
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/badges/verify")
                .header(
                    CONTENT_TYPE,
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(png_multipart(boundary, &png)))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check the stale export still verifies but is flagged as superseded
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8_lossy(&body);
    assert!(body.contains("Authentic but superseded by a newer export"));
    assert!(!body.contains("Valid and active"));
}

#[tokio::test]
async fn test_verify_post_returns_current_local_award() {
    // Setup one resolvable current award
    let award = sample_user_badge();
    let user_badge_id = award.user_badge_id;
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .returning(move |_| Ok(Some(award.clone())));
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;
    let boundary = "BADGE-VERIFY-BOUNDARY";

    // Submit the opaque local award identifier as multipart form data
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/badges/verify")
                .header(
                    CONTENT_TYPE,
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(credential_multipart(boundary, user_badge_id)))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check verification renders current public identity without caching
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    let body = String::from_utf8_lossy(&body);
    assert!(body.contains("Valid and active"));
    assert!(body.contains("Ada"));
    assert!(body.contains("src=\"/images/badges/test-badge.png\""));
    assert!(body.contains("alt=\"Test Badge badge artwork\""));
    assert!(body.contains("datetime=\"2024-01-02T03:04:05+00:00\""));
    assert!(body.contains("January 2, 2024"));
}

#[tokio::test]
async fn test_verify_post_returns_uploaded_award() {
    // Issue and bake one portable credential using the router's signing key
    let award = sample_user_badge();
    let user_badge_id = award.user_badge_id;
    let server_cfg = badges_server_config();
    let badges_manager =
        BadgesManager::new(&server_cfg.base_url, server_cfg.badges.as_ref().unwrap());
    let credential = badges_manager
        .issue_credential(CredentialInput {
            award: &award,
            created_at: Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
            email_identity: None,
        })
        .await
        .unwrap();
    let credential = serde_json::to_vec(&credential).unwrap();
    let png = png::bake(&sample_png(), &credential).unwrap();

    // Setup the matching durable award and verification page settings
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .returning(move |_| Ok(Some(award.clone())));
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_server_cfg(server_cfg)
        .build()
        .await;
    let boundary = "BADGE-PNG-VERIFY-BOUNDARY";

    // Submit the exported PNG as multipart form data
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/badges/verify")
                .header(
                    CONTENT_TYPE,
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(png_multipart(boundary, &png)))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check portable verification renders the matched local artwork and award date
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    let body = String::from_utf8_lossy(&body);
    assert!(body.contains("Valid and active"));
    assert!(body.contains("src=\"/images/badges/test-badge.png\""));
    assert!(body.contains("datetime=\"2024-01-02T03:04:05+00:00\""));
    assert!(body.contains("January 2, 2024"));
}

#[tokio::test]
async fn test_verify_post_returns_uploaded_email_bound_award_without_rendering_identity() {
    // Issue and bake one email-bound export credential matching the stored binding
    let identity_hash = "fa4e696fed1caae3ce9bda21a14b5d7960f8ef36bf1566164dafb09f4c8ac324";
    let identity_salt = "0123456789abcdef0123456789abcdef";
    let mut award = sample_user_badge();
    award.identity_bound_at = Some(Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap());
    award.identity_hash = Some(identity_hash.to_string());
    award.identity_salt = Some(identity_salt.to_string());
    let user_badge_id = award.user_badge_id;
    let server_cfg = badges_server_config();
    let badges_manager =
        BadgesManager::new(&server_cfg.base_url, server_cfg.badges.as_ref().unwrap());
    let credential = badges_manager
        .issue_credential(CredentialInput {
            award: &award,
            created_at: Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
            email_identity: Some(EmailIdentity {
                hash: identity_hash.to_string(),
                salt: identity_salt.to_string(),
            }),
        })
        .await
        .unwrap();
    let credential = serde_json::to_vec(&credential).unwrap();
    let png = png::bake(&sample_png(), &credential).unwrap();

    // Setup the matching durable award and verification page settings
    let mut db = MockDB::new();
    db.expect_get_public_user_badge()
        .times(1)
        .withf(move |id| *id == user_badge_id)
        .returning(move |_| Ok(Some(award.clone())));
    db.expect_get_site_settings()
        .times(1)
        .return_once(|| Ok(sample_site_settings()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_server_cfg(server_cfg)
        .build()
        .await;
    let boundary = "BADGE-PNG-VERIFY-BOUNDARY";

    // Submit the exported email-bound PNG as multipart form data
    let response = router
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/badges/verify")
                .header(
                    CONTENT_TYPE,
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(png_multipart(boundary, &png)))
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check the current email-bound export verifies without rendering its identity
    assert_eq!(parts.status, StatusCode::OK);
    let body = String::from_utf8_lossy(&body);
    assert!(body.contains("Valid and active"));
    assert!(!body.contains("superseded"));
    assert!(!body.contains(identity_hash));
    assert!(!body.contains(identity_salt));
    assert!(!body.to_lowercase().contains("recipient@example.test"));
}

// Helpers.

/// Build a server configuration with one active deterministic key identifier.
fn badges_server_config() -> HttpServerConfig {
    HttpServerConfig {
        badges: Some(BadgesConfig {
            signing_key: BadgeSigningKeyConfig {
                key_id: "test-key".to_string(),
                private_jwk: JWK::generate_ed25519().unwrap(),
            },
            verification_keys: vec![],
        }),
        base_url: "https://badges.example.test".to_string(),
        ..HttpServerConfig::default()
    }
}

/// Encode one credential-reference multipart body.
fn credential_multipart(boundary: &str, user_badge_id: Uuid) -> String {
    format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"credential\"\r\n\r\n{user_badge_id}\r\n--{boundary}--\r\n"
    )
}

/// Encodes one PNG-upload multipart body.
fn png_multipart(boundary: &str, png: &[u8]) -> Vec<u8> {
    let mut body = format!(
        "--{boundary}\r\nContent-Disposition: form-data; name=\"png\"; filename=\"badge.png\"\r\nContent-Type: image/png\r\n\r\n"
    )
    .into_bytes();
    body.extend_from_slice(png);
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    body
}

/// Build one deterministic current status-list row.
fn sample_badge_status_list() -> BadgeStatusList {
    BadgeStatusList {
        badge_status_list_id: Uuid::new_v4(),
        group_id: Uuid::new_v4(),
        revoked_indexes: vec![1],
    }
}

/// Encodes valid 512×512 PNG artwork.
fn sample_png() -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(512, 512)
        .write_to(&mut output, ImageFormat::Png)
        .unwrap();
    output.into_inner()
}

/// Build one active public badge fixture.
fn sample_user_badge() -> UserBadge {
    let group_id = Uuid::new_v4();
    UserBadge {
        awarded_at: Utc.with_ymd_and_hms(2024, 1, 2, 3, 4, 5).unwrap(),
        badge_status_list_id: Uuid::new_v4(),
        display_order: 0,
        group_id,
        is_listed: true,
        snapshot: BadgeSnapshot {
            criteria: "Attend".to_string(),
            description: "Test badge description".to_string(),
            image_file_name: "test-badge.png".to_string(),
            issuer: BadgeSnapshotIssuer {
                community_id: Uuid::new_v4(),
                community_name: "Test Community".to_string(),
                group_id,
                group_name: "Test Group".to_string(),
            },
            name: "Test Badge".to_string(),
        },
        status_list_index: 1,
        user_badge_id: Uuid::new_v4(),

        badge_id: Some(Uuid::new_v4()),
        event_id: Some(Uuid::new_v4()),
        event_name: Some("Test Event".to_string()),
        identity_bound_at: None,
        identity_hash: None,
        identity_salt: None,
        recipient_name: Some("Ada".to_string()),
        recipient_username: Some("ada".to_string()),
        revocation_reason: None,
        revoked_at: None,
        revoked_by_user_id: None,
        user_id: Some(Uuid::new_v4()),
    }
}
