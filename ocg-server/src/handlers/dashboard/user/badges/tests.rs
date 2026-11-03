use axum::http::{
    StatusCode,
    header::{CONTENT_DISPOSITION, CONTENT_TYPE},
};
use chrono::{DateTime, TimeZone, Utc};
use serde_json::json;
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::mock::MockDB,
    handlers::tests::*,
    services::{
        badges::{BadgesManager, SsiBadgesManager, png},
        images::MockImageStorage,
    },
    test_util::sample_png,
    types::{
        badges::{BadgeSnapshot, BadgeSnapshotIssuer, UserBadge, UserBadgeIdentity},
        images::Image,
    },
    util::compute_hash,
};

#[tokio::test]
async fn test_export_missing_artwork_returns_not_found() {
    // Setup an authenticated owner whose active award references missing artwork
    let ids = DashboardIds::new();
    let user_badge_id = Uuid::new_v4();
    let award = sample_user_badge(user_badge_id, ids.user_id);
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == ids.user_id && *badge_id == user_badge_id)
        .return_once(move |_, _| Ok(Some(award)));
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .returning(|_| Box::pin(async { Ok(None) }));
    let router = TestRouterBuilder::new(db).with_image_storage(storage).build().await;

    // Request a PNG export whose immutable source artwork is unavailable
    let request = get_request(
        &format!("/dashboard/user/badges/{user_badge_id}/export"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check missing source artwork is reported without exposing storage details
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_export_revoked_badge_returns_not_found() {
    // Setup an authenticated owner whose requested award is already revoked
    let ids = DashboardIds::new();
    let user_badge_id = Uuid::new_v4();
    let award = sample_revoked_user_badge(user_badge_id, ids.user_id);
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == ids.user_id && *badge_id == user_badge_id)
        .return_once(move |_, _| Ok(Some(award)));
    let mut storage = MockImageStorage::new();
    storage.expect_get().never();
    let router = TestRouterBuilder::new(db).with_image_storage(storage).build().await;

    // Request a PNG export for a revoked credential
    let request = get_request(
        &format!("/dashboard/user/badges/{user_badge_id}/export"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check revoked awards are hidden before artwork loading or signing
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_export_success() {
    // Setup an authenticated owner, active award, signing key, and valid artwork
    let config = sample_badges_cfg();
    let base_url = "https://badges.example.test";
    let verification_manager = SsiBadgesManager::new(base_url, &config);
    let ids = DashboardIds::new();
    let user_badge_id = Uuid::new_v4();
    let award = sample_user_badge(user_badge_id, ids.user_id);
    let badge_status_list_id = award.badge_status_list_id;
    let identity_salt = "0123456789abcdef0123456789abcdef";
    let identity_hash = compute_hash(format!("user@example.test{identity_salt}").as_bytes());
    let bound_hash = identity_hash.clone();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == ids.user_id && *badge_id == user_badge_id)
        .return_once(move |_, _| Ok(Some(award)));
    db.expect_refresh_user_badge_identity()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == ids.user_id && *badge_id == user_badge_id)
        .return_once(move |_, _| {
            Ok(UserBadgeIdentity {
                identity_bound_at: Utc.with_ymd_and_hms(2024, 2, 3, 4, 5, 6).unwrap(),
                identity_hash: bound_hash,
                identity_salt: identity_salt.to_string(),
            })
        });
    let mut storage = MockImageStorage::new();
    storage
        .expect_get()
        .times(1)
        .withf(|file_name| file_name == "badge.png")
        .return_once(|_| {
            Box::pin(async {
                Ok(Some(Image {
                    bytes: sample_png(512, 512),
                    content_type: "image/png".to_string(),
                }))
            })
        });
    let router = TestRouterBuilder::new(db)
        .with_image_storage(storage)
        .with_server_cfg(HttpServerConfig {
            badges: Some(config),
            base_url: base_url.to_string(),
            ..HttpServerConfig::default()
        })
        .build()
        .await;

    // Request the composed signed PNG export
    let request = get_request(
        &format!("/dashboard/user/badges/{user_badge_id}/export"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check download headers and the embedded credential proof
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(parts.headers.get(CONTENT_TYPE).unwrap(), "image/png");
    assert_eq!(
        parts.headers.get(CONTENT_DISPOSITION).unwrap(),
        &format!("attachment; filename=\"badge-{user_badge_id}.png\"")
    );
    let credential = serde_json::from_slice(&png::extract(&bytes).unwrap()).unwrap();
    let verified = verification_manager.verify_credential(&credential).await.unwrap();
    assert_eq!(verified.user_badge_id, user_badge_id);
    assert_eq!(verified.status_list_id, badge_status_list_id);

    // Check the credential embeds the persisted salted email identity binding
    // pinned to the binding time
    let identifier = credential["credentialSubject"]["identifier"].as_array().unwrap();
    assert_eq!(identifier.len(), 1);
    let entry = &identifier[0];
    assert_eq!(entry["type"], json!("IdentityObject"));
    assert_eq!(entry["hashed"], json!(true));
    assert_eq!(
        entry["identityHash"],
        json!(format!("sha256${identity_hash}"))
    );
    assert_eq!(entry["identityType"], json!("emailAddress"));
    assert_eq!(entry["salt"], json!(identity_salt));
    assert_eq!(
        credential["proof"][0]["created"],
        "2024-02-03T04:05:06.000Z"
    );
    assert!(!credential.to_string().contains("user@example.test"));
}

#[tokio::test]
async fn test_export_unknown_badge_returns_not_found() {
    // Setup an authenticated user without the requested active award
    let ids = DashboardIds::new();
    let user_badge_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_get_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == ids.user_id && *badge_id == user_badge_id)
        .return_once(|_, _| Ok(None));
    let router = TestRouterBuilder::new(db).build().await;

    // Request a PNG export for the missing award
    let request = get_request(
        &format!("/dashboard/user/badges/{user_badge_id}/export"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check ownership failures remain indistinguishable from missing awards
    assert_empty_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_revoke_success() {
    // Setup an authenticated badge owner
    let ids = DashboardIds::new();
    let user_badge_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_revoke_user_badge()
        .times(1)
        .withf(move |owner_id, badge_id| *owner_id == ids.user_id && *badge_id == user_badge_id)
        .return_once(|_, _| Ok(()));
    let router = TestRouterBuilder::new(db).build().await;

    // Permanently revoke the owned credential
    let request = empty_request(
        "DELETE",
        &format!("/dashboard/user/badges/{user_badge_id}"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check the mutation response is empty
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_listing_success() {
    // Setup an authenticated badge owner
    let ids = DashboardIds::new();
    let user_badge_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_badge_listing()
        .times(1)
        .withf(move |owner_id, badge_id, is_listed| {
            *owner_id == ids.user_id && *badge_id == user_badge_id && !is_listed
        })
        .return_once(|_, _, _| Ok(()));
    let router = TestRouterBuilder::new(db).build().await;

    // Hide the badge from public profile discovery
    let request = json_request(
        "PUT",
        &format!("/dashboard/user/badges/{user_badge_id}/listing"),
        ids.session_id,
        &json!({"is_listed": false}),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the mutation response is empty
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn test_update_order_success() {
    // Setup an authenticated badge owner and complete order
    let first_badge_id = Uuid::new_v4();
    let second_badge_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_update_user_badges_order()
        .times(1)
        .withf(move |owner_id, badge_ids| {
            *owner_id == ids.user_id && badge_ids == [second_badge_id, first_badge_id]
        })
        .return_once(|_, _| Ok(()));
    let router = TestRouterBuilder::new(db).build().await;

    // Persist the complete user-selected order
    let request = json_request(
        "PUT",
        "/dashboard/user/badges/order",
        ids.session_id,
        &json!({"user_badge_ids": [second_badge_id, first_badge_id]}),
    );
    let (parts, bytes) = send(router, request).await;

    // Check the mutation response is empty
    assert_empty_response(&parts, &bytes, StatusCode::NO_CONTENT);
}

// Helpers.

/// Build one revoked badge owned by the supplied user.
fn sample_revoked_user_badge(user_badge_id: Uuid, user_id: Uuid) -> UserBadge {
    UserBadge {
        revocation_reason: Some("user revoked badge".to_string()),
        revoked_at: Some(DateTime::UNIX_EPOCH),
        revoked_by_user_id: Some(user_id),
        ..sample_user_badge(user_badge_id, user_id)
    }
}

/// Build one active badge owned by the supplied user.
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
        identity_bound_at: None,
        identity_hash: None,
        identity_salt: None,
        recipient_name: None,
        recipient_username: None,
        revocation_reason: None,
        revoked_at: None,
        revoked_by_user_id: None,
        user_id: Some(user_id),
    }
}
