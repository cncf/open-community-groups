use axum::{
    body::{Body, to_bytes},
    http::{
        HeaderMap, HeaderValue, Request, StatusCode,
        header::{ACCEPT, CACHE_CONTROL, CONTENT_TYPE},
    },
};
use chrono::{TimeZone, Utc};
use serde_json::{Value, json};
use ssi_jwk::JWK;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::{BadgeSigningKeyConfig, BadgesConfig, HttpServerConfig},
    db::mock::MockDB,
    handlers::tests::{TestRouterBuilder, sample_site_settings},
    services::notifications::MockNotificationsManager,
    types::badges::{
        BadgeSnapshot, BadgeSnapshotIssuer, BadgeStatusList, PublicUserBadge, UserBadge,
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
async fn test_credential_json_ld_response_is_signed_and_uncached() {
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

    // Check the signed JSON-LD and private-cache boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CONTENT_TYPE).unwrap(),
        "application/vc+ld+json"
    );
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    assert_eq!(
        body["id"],
        format!("https://badges.example.test/badges/credentials/{user_badge_id}")
    );
    assert_eq!(body["proof"]["cryptosuite"], "eddsa-rdfc-2022");
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
async fn test_issuer_returns_stable_public_profile() {
    // Setup a public router without configured signing material
    let group_id = Uuid::new_v4();
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
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
    assert!(
        body["id"]
            .as_str()
            .unwrap()
            .ends_with(&format!("/badges/issuers/{group_id}"))
    );
    assert_eq!(body["type"], "Profile");
    assert_eq!(body["assertionMethod"], json!([]));
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
    assert_eq!(body["proof"]["cryptosuite"], "eddsa-rdfc-2022");
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
    let community_id = Uuid::new_v4();
    let award = sample_user_badge();
    let expected = vec![PublicUserBadge {
        awarded_at: award.awarded_at,
        group_id: award.group_id,
        snapshot: award.snapshot,
        user_badge_id: award.user_badge_id,
    }];
    let output = expected.clone();
    let mut db = MockDB::new();
    db.expect_get_community_id_by_name()
        .times(1)
        .withf(|name| name == "test-community")
        .return_once(move |_| Ok(Some(community_id)));
    db.expect_list_user_public_badges()
        .times(1)
        .withf(move |id, username| *id == community_id && username == "ada")
        .return_once(move |_, _| Ok(output));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request the community-scoped public projection
    let response = router
        .oneshot(
            Request::builder()
                .uri("/communities/test-community/users/ada/badges")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: Vec<PublicUserBadge> =
        serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check only the public DTO crosses the uncached handler boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(
        parts.headers.get(CACHE_CONTROL).unwrap(),
        CACHE_CONTROL_NO_STORE
    );
    assert_eq!(body, expected);
}

#[tokio::test]
async fn test_verification_key_returns_allowlisted_multikey() {
    // Setup one active allowlisted verification key
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
        .with_server_cfg(badges_server_config())
        .build()
        .await;

    // Request the stable public verification method
    let response = router
        .oneshot(
            Request::builder()
                .uri("/badges/keys/test-key")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Check the Multikey response and public cache boundary
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers.get(CONTENT_TYPE).unwrap(), "application/json");
    assert!(parts.headers.get(CACHE_CONTROL).is_some());
    assert_eq!(body["type"], "Multikey");
    assert_eq!(
        body["id"],
        "https://badges.example.test/badges/keys/test-key"
    );
}

#[tokio::test]
async fn test_verification_key_unknown_id_returns_not_found() {
    // Setup a public router without an allowlisted key
    let router = TestRouterBuilder::new(MockDB::new(), MockNotificationsManager::new())
        .build()
        .await;

    // Request an unconfigured verification method
    let response = router
        .oneshot(
            Request::builder()
                .uri("/badges/keys/unknown-key")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check arbitrary key identifiers are not published
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
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

/// Build one deterministic current status-list row.
fn sample_badge_status_list() -> BadgeStatusList {
    BadgeStatusList {
        badge_status_list_id: Uuid::new_v4(),
        group_id: Uuid::new_v4(),
        revoked_indexes: vec![1],
    }
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
        recipient_name: Some("Ada".to_string()),
        recipient_username: Some("ada".to_string()),
        revocation_reason: None,
        revoked_at: None,
        revoked_by_user_id: None,
        user_id: Some(Uuid::new_v4()),
    }
}
