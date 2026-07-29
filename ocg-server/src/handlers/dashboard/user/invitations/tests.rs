use anyhow::anyhow;
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header::COOKIE},
};
use axum_login::tower_sessions::session;
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

use crate::{
    db::mock::MockDB,
    handlers::{
        auth::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
        tests::*,
    },
    services::notifications::MockNotificationsManager,
    types::event::EventEnrollmentReconciliationOutcome,
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let community_invitations = vec![sample_community_invitation(community_id)];
    let event_invitations = vec![sample_event_invitation(Uuid::new_v4())];
    let group_invitations = vec![sample_group_invitation(Uuid::new_v4())];

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_community_team_invitations()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(community_invitations.clone()));
    db.expect_list_user_event_invitations()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(event_invitations.clone()));
    db.expect_list_user_group_team_invitations()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(group_invitations.clone()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/invitations")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_list_page_db_error() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let community_invitations = vec![sample_community_invitation(community_id)];
    let event_invitations = vec![sample_event_invitation(Uuid::new_v4())];

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_list_user_community_team_invitations()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(community_invitations.clone()));
    db.expect_list_user_event_invitations()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(event_invitations.clone()));
    db.expect_list_user_group_team_invitations()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Err(anyhow!("db error")));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("GET")
        .uri("/dashboard/user/invitations")
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_response(&parts, &bytes, StatusCode::INTERNAL_SERVER_ERROR);
}

#[tokio::test]
async fn test_accept_community_team_invitation_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_accept_community_team_invitation()
        .times(1)
        .withf(move |uid, cid| *uid == user_id && *cid == community_id)
        .returning(|_, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && message_matches(record, "Team invitation accepted.")
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(community_id))
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(group_id))
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/invitations/community/{community_id}/accept"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_accept_event_admission_offer_route_is_removed() {
    // Setup a request for the deleted route
    let admission_offer_id = Uuid::new_v4();

    // Setup the not-found page database expectation
    let mut db = MockDB::new();
    db.expect_get_site_settings()
        .times(1)
        .returning(|| Ok(sample_site_settings()));

    // Send the former route through the application router
    let router = TestRouterBuilder::new(db, MockNotificationsManager::new())
        .build()
        .await;
    let response = router
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!(
                    "/dashboard/user/invitations/event-offers/{admission_offer_id}/accept"
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Check the removed route stays unavailable
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_accept_group_team_invitation_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_accept_group_team_invitation()
        .times(1)
        .withf(move |uid, gid| *uid == user_id && *gid == group_id)
        .returning(|_, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id
                && message_matches(record, "Team invitation accepted.")
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(community_id))
                && record
                    .data
                    .get(SELECTED_GROUP_ID_KEY)
                    .is_some_and(|value| value == &json!(group_id))
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/invitations/group/{group_id}/accept"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_decline_event_admission_offer_success() {
    // Setup identifiers and data structures
    let admission_offer_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_decline_event_admission_offer()
        .times(1)
        .withf(move |uid, oid, provider| {
            *uid == user_id
                && *oid == admission_offer_id
                && *provider == Some(crate::types::payments::PaymentProvider::Stripe)
        })
        .returning(move |_, _, _| {
            Ok(EventEnrollmentReconciliationOutcome {
                community_id: Uuid::new_v4(),
                event_id: Uuid::new_v4(),
                group_id: Uuid::new_v4(),
            })
        });
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id && message_matches(record, "Event offer declined.")
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/invitations/event-offers/{admission_offer_id}/decline"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_reject_community_team_invitation_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_reject_community_team_invitation()
        .times(1)
        .withf(move |uid, cid| *uid == user_id && *cid == community_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id && message_matches(record, "Team invitation rejected.")
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/invitations/community/{community_id}/reject"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_reject_group_team_invitation_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let session_id = session::Id::default();
    let user_id = Uuid::new_v4();
    let auth_hash = "hash".to_string();
    let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);

    // Setup database mock
    let mut db = MockDB::new();
    db.expect_get_session()
        .times(1)
        .withf(move |id| *id == session_id)
        .returning(move |_| Ok(Some(session_record.clone())));
    db.expect_get_user_by_id()
        .times(1)
        .withf(move |id| *id == user_id)
        .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash))));
    db.expect_reject_group_team_invitation()
        .times(1)
        .withf(move |uid, gid| *uid == user_id && *gid == group_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == session_id && message_matches(record, "Team invitation rejected.")
        })
        .returning(|_| Ok(()));

    // Setup notifications manager mock
    let nm = MockNotificationsManager::new();

    // Setup router and send request
    let router = TestRouterBuilder::new(db, nm).build().await;
    let request = Request::builder()
        .method("PUT")
        .uri(format!(
            "/dashboard/user/invitations/group/{group_id}/reject"
        ))
        .header(COOKIE, format!("id={session_id}"))
        .body(Body::empty())
        .unwrap();
    let response = router.oneshot(request).await.unwrap();
    let (parts, body) = response.into_parts();
    let bytes = to_bytes(body, usize::MAX).await.unwrap();

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}
