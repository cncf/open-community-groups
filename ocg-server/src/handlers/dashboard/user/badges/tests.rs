use std::io::Cursor;

use axum::{
    body::{Body, to_bytes},
    http::{
        Request, StatusCode,
        header::{CONTENT_DISPOSITION, CONTENT_TYPE, COOKIE},
    },
};
use axum_login::tower_sessions::session;
use chrono::DateTime;
use image::{DynamicImage, ImageFormat};
use serde_json::json;
use ssi_jwk::JWK;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    config::{BadgeSigningKeyConfig, BadgesConfig, HttpServerConfig},
    db::mock::MockDB,
    handlers::tests::{TestRouterBuilder, assert_empty_response, expect_authenticated_session},
    services::{
        badges::{BadgesManager, png},
        images::{Image, MockImageStorage},
        notifications::MockNotificationsManager,
    },
    types::badges::{BadgeSnapshot, BadgeSnapshotIssuer, UserBadge},
    util::compute_hash,
};

#[tokio::test]
async fn test_export_missing_artwork_returns_not_found() {
    // Setup an authenticated owner whose active award references missing artwork
    let session_id = session::Id::default();
    let user_badge_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let award = sample_active_user_badge(user_badge_id, user_id);
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == user_id && *badge_id == user_badge_id)
        .return_once(move |_, _| Ok(Some(award)));
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .returning(|_| Box::pin(async { Ok(None) }));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .build()
        .await;

    // Request a PNG export whose immutable source artwork is unavailable
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/dashboard/user/badges/{user_badge_id}/export"))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check missing source artwork is reported without exposing storage details
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_export_revoked_badge_returns_not_found() {
    // Setup an authenticated owner whose requested award is already revoked
    let session_id = session::Id::default();
    let user_badge_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let award = sample_user_badge(user_badge_id, user_id);
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == user_id && *badge_id == user_badge_id)
        .return_once(move |_, _| Ok(Some(award)));
    let mut storage = MockImageStorage::new();
    storage.expect_get().never();
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .build()
        .await;

    // Request a PNG export for a revoked credential
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/dashboard/user/badges/{user_badge_id}/export"))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check revoked awards are hidden before artwork loading or signing
    assert_empty_response(&parts, &body, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_export_success() {
    // Setup an authenticated owner, active award, signing key, and valid artwork
    let config = badge_config();
    let base_url = "https://badges.example.test";
    let verification_manager = BadgesManager::new(base_url, &config);
    let session_id = session::Id::default();
    let user_badge_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let award = sample_active_user_badge(user_badge_id, user_id);
    let badge_status_list_id = award.badge_status_list_id;
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == user_id && *badge_id == user_badge_id)
        .return_once(move |_, _| Ok(Some(award)));
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| {
            Box::pin(async {
                Ok(Some(Image {
                    bytes: png_bytes(),
                    content_type: "image/png".to_string(),
                }))
            })
        });
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .with_image_storage(storage)
        .with_server_cfg(HttpServerConfig {
            badges: Some(config),
            base_url: base_url.to_string(),
            ..HttpServerConfig::default()
        })
        .build()
        .await;

    // Request the composed signed PNG export
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/dashboard/user/badges/{user_badge_id}/export"))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check download headers and the embedded credential proof
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers.get(CONTENT_TYPE).unwrap(), "image/png");
    assert_eq!(
        parts.headers.get(CONTENT_DISPOSITION).unwrap(),
        &format!("attachment; filename=\"badge-{user_badge_id}.png\"")
    );
    let credential = serde_json::from_slice(&png::extract(&body).unwrap()).unwrap();
    let verified = verification_manager.verify_credential(&credential).await.unwrap();
    assert_eq!(verified.user_badge_id, user_badge_id);
    assert_eq!(verified.status_list_id, badge_status_list_id);

    // Check the credential binds a salted hash of the owner's account email
    let identifier = credential["credentialSubject"]["identifier"].as_array().unwrap();
    assert_eq!(identifier.len(), 1);
    let entry = &identifier[0];
    let salt = entry["salt"].as_str().unwrap();
    let expected_hash = format!(
        "sha256${}",
        compute_hash(format!("user@example.test{salt}").as_bytes())
    );
    assert_eq!(entry["type"], json!("IdentityObject"));
    assert_eq!(entry["hashed"], json!(true));
    assert_eq!(entry["identityHash"], json!(expected_hash));
    assert_eq!(entry["identityType"], json!("emailAddress"));
    assert_eq!(salt.len(), 32);
    assert!(!credential.to_string().contains("user@example.test"));
}

#[tokio::test]
async fn test_export_unknown_badge_returns_not_found() {
    // Setup an authenticated user without the requested active award
    let session_id = session::Id::default();
    let user_badge_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == user_id && *badge_id == user_badge_id)
        .return_once(|_, _| Ok(None));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request a PNG export for the missing award
    let response = router
        .oneshot(
            Request::builder()
                .uri(format!("/dashboard/user/badges/{user_badge_id}/export"))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check ownership failures remain indistinguishable from missing awards
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_list_page_success() {
    // Setup an authenticated user with no active badges
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_list_user_badges()
        .times(1)
        .withf(move |id| *id == user_id)
        .return_once(|_| Ok(vec![]));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Request the badge dashboard fragment
    let response = router
        .oneshot(
            Request::builder()
                .uri("/dashboard/user/badges")
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Check the empty dashboard state renders as HTML
    assert_eq!(parts.status, StatusCode::OK);
    assert!(!body.is_empty());
}

#[tokio::test]
async fn test_revoke_success() {
    // Setup an authenticated badge owner
    let session_id = session::Id::default();
    let user_badge_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_revoke_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == user_id && *badge_id == user_badge_id)
        .return_once(|_, _| Ok(()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Permanently revoke the owned credential
    let response = router
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/dashboard/user/badges/{user_badge_id}"))
                .header(COOKIE, format!("id={session_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check the mutation response is empty
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_listing_success() {
    // Setup an authenticated badge owner
    let session_id = session::Id::default();
    let user_badge_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_update_user_badge_listing()
        .times(1)
        .withf(move |owner_id, badge_id, is_listed| {
            *owner_id == user_id && *badge_id == user_badge_id && !is_listed
        })
        .return_once(|_, _, _| Ok(()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Hide the badge from public profile discovery
    let response = router
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/dashboard/user/badges/{user_badge_id}/listing"))
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(json!({"is_listed": false}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    // Check the mutation response is empty
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_order_success() {
    // Setup an authenticated badge owner and complete order
    let first_badge_id = Uuid::new_v4();
    let second_badge_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_authenticated_session(&mut db, session_id, user_id);
    db.expect_update_user_badges_order()
        .times(1)
        .withf(move |owner_id, badge_ids| {
            *owner_id == user_id && badge_ids == [second_badge_id, first_badge_id]
        })
        .return_once(|_, _| Ok(()));
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;

    // Persist the complete user-selected order
    let response = router
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/dashboard/user/badges/order")
                .header(COOKIE, format!("id={session_id}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({"user_badge_ids": [second_badge_id, first_badge_id]}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    // Check the mutation response is empty
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

// Helpers.

/// Build a valid active badge signing configuration.
fn badge_config() -> BadgesConfig {
    BadgesConfig {
        signing_key: BadgeSigningKeyConfig {
            key_id: "export-test".to_string(),
            private_jwk: JWK::generate_ed25519().unwrap(),
        },
        verification_keys: vec![],
    }
}

/// Encode valid badge artwork.
fn png_bytes() -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(512, 512)
        .write_to(&mut output, ImageFormat::Png)
        .unwrap();
    output.into_inner()
}

/// Build one active badge owned by the supplied user.
fn sample_active_user_badge(user_badge_id: Uuid, user_id: Uuid) -> UserBadge {
    let mut badge = sample_user_badge(user_badge_id, user_id);
    badge.revocation_reason = None;
    badge.revoked_at = None;
    badge.revoked_by_user_id = None;
    badge
}

/// Build one revoked badge owned by the supplied user.
fn sample_user_badge(user_badge_id: Uuid, user_id: Uuid) -> UserBadge {
    let group_id = Uuid::new_v4();
    UserBadge {
        awarded_at: DateTime::UNIX_EPOCH,
        badge_status_list_id: Uuid::new_v4(),
        display_order: 0,
        group_id,
        is_listed: false,
        snapshot: BadgeSnapshot {
            criteria: "Attend".to_string(),
            description: "Test badge".to_string(),
            image_file_name: "badge.png".to_string(),
            issuer: BadgeSnapshotIssuer {
                community_id: Uuid::new_v4(),
                community_name: "Test Community".to_string(),
                group_id,
                group_name: "Test Group".to_string(),
            },
            name: "Participant".to_string(),
        },
        status_list_index: 1,
        user_badge_id,

        badge_id: Some(Uuid::new_v4()),
        event_id: None,
        event_name: None,
        recipient_name: None,
        recipient_username: None,
        revocation_reason: Some("user revoked badge".to_string()),
        revoked_at: Some(DateTime::UNIX_EPOCH),
        revoked_by_user_id: Some(user_id),
        user_id: Some(user_id),
    }
}
