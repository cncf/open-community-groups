use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use chrono::Utc;
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::{
        TestRouterBuilder, assert_html_response, sample_auth_user, sample_session_record,
    },
    services::notifications::MockNotificationsManager,
    templates::dashboard::group::check_in::{CheckInAttendee, CheckInOutcome, CheckInScanResult},
    types::permissions::GroupPermission,
};

use super::{parse_credential, scan_database_error_response};

#[tokio::test]
async fn test_list_page_returns_group_check_in_fragment() {
    // Setup an authorized group scanner list request
    let community_id = Uuid::from_u128(1);
    let group_id = Uuid::from_u128(2);
    let session_id = session::Id::default();
    let user_id = Uuid::from_u128(3);
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::CheckInsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_list_group_check_in_events()
        .times(1)
        .withf(move |gid| *gid == group_id)
        .returning(|_| Ok(vec![]));

    // Request the group check-in fragment
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/group/check-in")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let body = to_bytes(body, usize::MAX).await.unwrap();

    // Verify the fragment renders its empty scanner state
    assert_html_response(&parts, &body, StatusCode::OK);
    assert!(String::from_utf8_lossy(&body).contains("No events available for check-in"));
}

#[test]
fn test_parse_credential_accepts_versioned_payload() {
    // Setup a versioned credential
    let event_id = Uuid::from_u128(1);
    let check_in_code = Uuid::from_u128(2);

    // Parse and verify the credential identifiers
    assert_eq!(
        parse_credential(&format!("ocg-check-in:v1:{event_id}:{check_in_code}")),
        Ok((event_id, check_in_code))
    );
}

#[test]
fn test_parse_credential_rejects_extra_fields() {
    // Setup a credential carrying an unexpected field
    let event_id = Uuid::from_u128(1);
    let check_in_code = Uuid::from_u128(2);

    // Parse and reject the credential
    assert_eq!(
        parse_credential(&format!("ocg-check-in:v1:{event_id}:{check_in_code}:extra")),
        Err(())
    );
}

#[test]
fn test_parse_credential_rejects_unknown_version() {
    // Parse and reject an unsupported credential version
    assert_eq!(
        parse_credential(
            "ocg-check-in:v2:00000000-0000-0000-0000-000000000001:00000000-0000-0000-0000-000000000002"
        ),
        Err(())
    );
}

#[tokio::test]
async fn test_scan_returns_already_checked_in_result() {
    // Exercise and verify the neutral duplicate-scan result
    assert_scan_result(CheckInOutcome::AlreadyCheckedIn, "already-checked-in").await;
}

#[tokio::test]
async fn test_scan_returns_checked_in_result() {
    // Exercise and verify the first-scan result
    assert_scan_result(CheckInOutcome::CheckedIn, "checked-in").await;
}

#[tokio::test]
async fn test_scan_returns_malformed_credential_error() {
    // Setup an authorized scanner request with an invalid credential envelope
    let (router, session_id) = scan_test_router(true).await;
    let event_id = Uuid::new_v4();
    let request = Request::builder()
        .method("POST")
        .uri(format!("/dashboard/group/events/{event_id}/check-ins/scan"))
        .header(COOKIE, format!("id={session_id}"))
        .header("content-type", "application/json")
        .body(Body::from(
            json!({ "credential": "not-a-code" }).to_string(),
        ))
        .unwrap();
    // Submit the invalid credential
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Verify the typed failure response
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["code"], "malformed-credential");
}

#[tokio::test]
async fn test_scan_returns_malformed_credential_for_invalid_json_shapes() {
    // Define extractor failures that must share the scanner error contract
    let cases = [
        ("{", true),
        ("{}", true),
        (r#"{"credential": 1}"#, true),
        (r#"{"credential": "unused"}"#, false),
    ];

    for (body, include_content_type) in cases {
        // Setup an independently authorized scanner request
        let (router, session_id) = scan_test_router(true).await;
        let event_id = Uuid::from_u128(10);
        let mut request = Request::builder()
            .method("POST")
            .uri(format!("/dashboard/group/events/{event_id}/check-ins/scan"))
            .header(COOKIE, format!("id={session_id}"));
        if include_content_type {
            request = request.header("content-type", "application/json");
        }

        // Submit the malformed JSON body
        let response = router.oneshot(request.body(Body::from(body)).unwrap()).await.unwrap();
        let (parts, body) = response.into_parts();
        let body: Value =
            serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

        // Verify every extractor failure is normalized
        assert_eq!(parts.status, StatusCode::BAD_REQUEST);
        assert_eq!(body["error"]["code"], "malformed-credential");
    }
}

#[tokio::test]
async fn test_scan_returns_mapped_database_domain_errors() {
    // Define every stable database error mapping
    let cases = [
        (
            "attendance is not confirmed",
            StatusCode::CONFLICT,
            "non-confirmed-attendance",
        ),
        (
            "check-in credential not found",
            StatusCode::UNPROCESSABLE_ENTITY,
            "unknown-code",
        ),
        (
            "event unavailable for check-in",
            StatusCode::CONFLICT,
            "unavailable-event",
        ),
    ];

    for (message, expected_status, expected_code) in cases {
        // Map and decode the typed response
        let response = scan_database_error_response(message).unwrap();
        let (parts, body) = response.into_parts();
        let body: Value =
            serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

        // Verify the stable status and error code
        assert_eq!(parts.status, expected_status);
        assert_eq!(body["error"]["code"], expected_code);
    }
}

#[tokio::test]
async fn test_scan_returns_wrong_event_error() {
    // Setup a credential for a different event
    let (router, session_id) = scan_test_router(true).await;
    let event_id = Uuid::new_v4();
    let other_event_id = Uuid::new_v4();
    let check_in_code = Uuid::new_v4();
    let request = Request::builder()
        .method("POST")
        .uri(format!("/dashboard/group/events/{event_id}/check-ins/scan"))
        .header(COOKIE, format!("id={session_id}"))
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "credential": format!("ocg-check-in:v1:{other_event_id}:{check_in_code}"),
            })
            .to_string(),
        ))
        .unwrap();
    // Submit the credential to the selected event
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Verify the typed event mismatch response
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["error"]["code"], "wrong-event");
}

#[tokio::test]
async fn test_scan_validates_check_in_permission() {
    // Setup a scanner request without check-in permission
    let (router, session_id) = scan_test_router(false).await;
    let event_id = Uuid::new_v4();
    let request = Request::builder()
        .method("POST")
        .uri(format!("/dashboard/group/events/{event_id}/check-ins/scan"))
        .header(COOKIE, format!("id={session_id}"))
        .header("content-type", "application/json")
        .body(Body::from(json!({ "credential": "unused" }).to_string()))
        .unwrap();
    // Submit the scanner request
    let response = router.oneshot(request).await.unwrap();

    // Verify the route permission guard
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// Helpers.

/// Exercises the successful scanner response for one database outcome.
async fn assert_scan_result(outcome: CheckInOutcome, expected_outcome: &str) {
    // Setup identities and database expectations
    let check_in_code = Uuid::from_u128(1);
    let community_id = Uuid::from_u128(2);
    let event_id = Uuid::from_u128(3);
    let group_id = Uuid::from_u128(4);
    let session_id = session::Id::default();
    let user_id = Uuid::from_u128(5);
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::CheckInsWrite
        })
        .returning(|_, _, _, _| Ok(true));
    db.expect_check_in_attendee_by_code()
        .times(1)
        .withf(move |actor, code, community, event, group| {
            *actor == user_id
                && *code == check_in_code
                && *community == community_id
                && *event == event_id
                && *group == group_id
        })
        .returning(move |_, _, _, _, _| {
            Ok(CheckInScanResult {
                attendee: CheckInAttendee {
                    username: "attendee".to_string(),
                    name: Some("Test Attendee".to_string()),
                    photo_url: None,
                },
                checked_in_at: Utc::now(),
                outcome,
                ticket_title: Some("General admission".to_string()),
            })
        });

    // Submit a valid credential
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let request = Request::builder()
        .method("POST")
        .uri(format!("/dashboard/group/events/{event_id}/check-ins/scan"))
        .header(COOKIE, format!("id={session_id}"))
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "credential": format!("ocg-check-in:v1:{event_id}:{check_in_code}"),
            })
            .to_string(),
        ))
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let body: Value = serde_json::from_slice(&to_bytes(body, usize::MAX).await.unwrap()).unwrap();

    // Verify the complete scanner response
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body["outcome"], expected_outcome);
    assert_eq!(body["attendee"]["name"], "Test Attendee");
    assert_eq!(body["attendee"]["photo_url"], Value::Null);
    assert!(body["checked_in_at"].is_number());
    assert_eq!(body["ticket_title"], "General admission");
}

/// Builds an authenticated scanner router with the selected permission result.
async fn scan_test_router(has_permission: bool) -> (axum::Router, session::Id) {
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(
        session_id,
        user_id,
        &auth_hash,
        Some(community_id),
        Some(group_id),
    );

    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_user_has_group_permission()
        .times(1)
        .withf(move |cid, gid, uid, permission| {
            *cid == community_id
                && *gid == group_id
                && *uid == user_id
                && permission == GroupPermission::CheckInsWrite
        })
        .returning(move |_, _, _, _| Ok(has_permission));
    if !has_permission {
        db.expect_user_has_group_permission()
            .times(1)
            .withf(move |cid, gid, uid, permission| {
                *cid == community_id
                    && *gid == group_id
                    && *uid == user_id
                    && permission == GroupPermission::Read
            })
            .returning(|_, _, _, _| Ok(true));
    }
    db.expect_check_in_attendee_by_code().never();

    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    (router, session_id)
}
