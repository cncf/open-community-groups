use axum::{
    Router,
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::CONTENT_TYPE},
};
use axum_login::tower_sessions::session;
use chrono::Utc;
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::tests::*,
    services::check_in::CheckInScanRejection,
    types::{
        dashboard::group::check_in::{CheckInAttendee, CheckInOutcome, CheckInScanResult},
        permissions::GroupPermission,
    },
};

use super::scan_rejection_response;

#[tokio::test]
async fn test_list_page_returns_group_check_in_fragment() {
    // Setup an authorized group scanner list request
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::CheckInsWrite);
    db.expect_list_group_check_in_events()
        .times(1)
        .withf(move |gid| *gid == ids.group_id)
        .returning(|_| Ok(vec![]));

    // Request the group check-in fragment
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/group/check-in", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Verify the fragment renders its empty scanner state
    assert_html_response(&parts, &bytes, StatusCode::OK);
    assert!(String::from_utf8_lossy(&bytes).contains("No events available for check-in"));
}

#[tokio::test]
async fn test_scan_returns_already_checked_in_result() {
    // Setup an authorized scanner whose attendee was already checked in
    let ids = DashboardIds::new();
    let check_in_code = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::CheckInsWrite);
    expect_check_in_attendee_by_code(
        &mut db,
        &ids,
        event_id,
        check_in_code,
        CheckInOutcome::AlreadyCheckedIn,
    );

    // Submit a valid credential
    let router = TestRouterBuilder::new(db).build().await;
    let request = scan_request(
        ids.session_id,
        event_id,
        &credential(event_id, check_in_code),
    );
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the neutral duplicate-scan result
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body["outcome"], "already-checked-in");
    assert_eq!(body["attendee"]["name"], "Test Attendee");
    assert_eq!(body["attendee"]["photo_url"], Value::Null);
    assert!(body["checked_in_at"].is_number());
    assert_eq!(body["ticket_title"], "General admission");
}

#[tokio::test]
async fn test_scan_returns_checked_in_result() {
    // Setup an authorized scanner whose attendee is checked in now
    let ids = DashboardIds::new();
    let check_in_code = Uuid::new_v4();
    let event_id = Uuid::new_v4();
    let mut db = MockDB::new();
    expect_group_access(&mut db, &ids, GroupPermission::CheckInsWrite);
    expect_check_in_attendee_by_code(
        &mut db,
        &ids,
        event_id,
        check_in_code,
        CheckInOutcome::CheckedIn,
    );

    // Submit a valid credential
    let router = TestRouterBuilder::new(db).build().await;
    let request = scan_request(
        ids.session_id,
        event_id,
        &credential(event_id, check_in_code),
    );
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the complete scanner response
    assert_eq!(parts.status, StatusCode::OK);
    assert_eq!(body["outcome"], "checked-in");
    assert_eq!(body["attendee"]["name"], "Test Attendee");
    assert_eq!(body["attendee"]["photo_url"], Value::Null);
    assert!(body["checked_in_at"].is_number());
    assert_eq!(body["ticket_title"], "General admission");
}

#[tokio::test]
async fn test_scan_returns_malformed_credential_error() {
    // Setup an authorized scanner request with an unparseable credential
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let router = scan_router_without_check_in(&ids).await;

    // Submit the invalid credential
    let request = scan_request(ids.session_id, event_id, "not-a-code");
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the typed failure response
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["code"], "malformed-credential");
}

#[tokio::test]
async fn test_scan_returns_malformed_credential_for_missing_credential() {
    // Setup an authorized scanner request without a credential field
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let router = scan_router_without_check_in(&ids).await;

    // Submit the JSON body without a credential
    let request = raw_scan_request(ids.session_id, event_id)
        .header(CONTENT_TYPE, "application/json")
        .body(Body::from("{}"))
        .unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the extractor failure is normalized
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["code"], "malformed-credential");
}

#[tokio::test]
async fn test_scan_returns_malformed_credential_for_non_string_credential() {
    // Setup an authorized scanner request with a numeric credential
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let router = scan_router_without_check_in(&ids).await;

    // Submit the non-string credential
    let request = raw_scan_request(ids.session_id, event_id)
        .header(CONTENT_TYPE, "application/json")
        .body(Body::from(r#"{"credential": 1}"#))
        .unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the extractor failure is normalized
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["code"], "malformed-credential");
}

#[tokio::test]
async fn test_scan_returns_malformed_credential_for_unterminated_json() {
    // Setup an authorized scanner request with an unterminated JSON body
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let router = scan_router_without_check_in(&ids).await;

    // Submit the unterminated JSON body
    let request = raw_scan_request(ids.session_id, event_id)
        .header(CONTENT_TYPE, "application/json")
        .body(Body::from("{"))
        .unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the extractor failure is normalized
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["code"], "malformed-credential");
}

#[tokio::test]
async fn test_scan_returns_malformed_credential_without_json_content_type() {
    // Setup an authorized scanner request without a JSON content type
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let router = scan_router_without_check_in(&ids).await;

    // Submit the body without a content type
    let request = raw_scan_request(ids.session_id, event_id)
        .body(Body::from(r#"{"credential": "unused"}"#))
        .unwrap();
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the extractor failure is normalized
    assert_eq!(parts.status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"]["code"], "malformed-credential");
}

#[tokio::test]
async fn test_scan_rejection_response_maps_every_rejection() {
    // Define every stable scanner rejection response
    let cases = [
        (
            CheckInScanRejection::NonConfirmedAttendance,
            StatusCode::CONFLICT,
            "non-confirmed-attendance",
            "This attendee no longer has confirmed attendance.",
        ),
        (
            CheckInScanRejection::UnavailableEvent,
            StatusCode::CONFLICT,
            "unavailable-event",
            "This event is not available for check-in.",
        ),
        (
            CheckInScanRejection::UnknownCode,
            StatusCode::UNPROCESSABLE_ENTITY,
            "unknown-code",
            "This check-in credential is not recognized.",
        ),
    ];

    for (rejection, expected_status, expected_code, expected_message) in cases {
        // Map and decode the typed response
        let response = scan_rejection_response(rejection);
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();
        let body: Value = serde_json::from_slice(&bytes).unwrap();

        // Verify the stable status, error code and message
        assert_eq!(parts.status, expected_status, "case: {rejection:?}");
        assert_eq!(body["error"]["code"], expected_code, "case: {rejection:?}");
        assert_eq!(
            body["error"]["message"], expected_message,
            "case: {rejection:?}"
        );
    }
}

#[tokio::test]
async fn test_scan_returns_wrong_event_error() {
    // Setup a credential for a different event
    let ids = DashboardIds::new();
    let event_id = Uuid::new_v4();
    let other_event_id = Uuid::new_v4();
    let router = scan_router_without_check_in(&ids).await;

    // Submit the credential to the selected event
    let request = scan_request(
        ids.session_id,
        event_id,
        &credential(other_event_id, Uuid::new_v4()),
    );
    let (parts, bytes) = send(router, request).await;
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Verify the typed event mismatch response
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["error"]["code"], "wrong-event");
}

// Helpers.

/// Returns the versioned credential for the event and check-in code.
fn credential(event_id: Uuid, check_in_code: Uuid) -> String {
    format!("ocg-check-in:v1:{event_id}:{check_in_code}")
}

/// Expects one check-in by code that returns the outcome for a sample attendee.
fn expect_check_in_attendee_by_code(
    db: &mut MockDB,
    ids: &DashboardIds,
    event_id: Uuid,
    check_in_code: Uuid,
    outcome: CheckInOutcome,
) {
    let ids = *ids;
    db.expect_check_in_attendee_by_code()
        .times(1)
        .withf(move |actor, code, community, event, group| {
            *actor == ids.user_id
                && *code == check_in_code
                && *community == ids.community_id
                && *event == event_id
                && *group == ids.group_id
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
}

/// Builds a scan request carrying the credential.
fn scan_request(session_id: session::Id, event_id: Uuid, credential: &str) -> Request<Body> {
    json_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/check-ins/scan"),
        session_id,
        &json!({ "credential": credential }),
    )
}

/// Builds an authenticated scan request without content type or body.
fn raw_scan_request(session_id: session::Id, event_id: Uuid) -> axum::http::request::Builder {
    authenticated_request(
        "POST",
        &format!("/dashboard/group/events/{event_id}/check-ins/scan"),
        session_id,
    )
}

/// Builds an authorized scanner router that must reject before checking in.
async fn scan_router_without_check_in(ids: &DashboardIds) -> Router {
    let mut db = MockDB::new();
    expect_group_access(&mut db, ids, GroupPermission::CheckInsWrite);
    db.expect_check_in_attendee_by_code().never();

    TestRouterBuilder::new(db).build().await
}
