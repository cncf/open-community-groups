use axum::{body::Body, http::StatusCode};
use serde_json::json;
use uuid::Uuid;

use crate::{
    db::mock::{MockDB, expect_site_settings},
    handlers::{
        auth::session_context::{SELECTED_COMMUNITY_ID_KEY, SELECTED_GROUP_ID_KEY},
        tests::*,
    },
    types::event::EventEnrollmentReconciliationOutcome,
};

#[tokio::test]
async fn test_list_page_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let community_invitations = vec![sample_community_invitation(community_id)];
    let event_invitations = vec![sample_event_invitation(Uuid::new_v4())];
    let group_invitations = vec![sample_group_invitation(Uuid::new_v4())];

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_list_user_community_team_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(community_invitations.clone()));
    db.expect_list_user_event_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(event_invitations.clone()));
    db.expect_list_user_group_team_invitations()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(group_invitations.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/user/invitations", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_html_response(&parts, &bytes, StatusCode::OK);
}

#[tokio::test]
async fn test_accept_community_team_invitation_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_accept_community_team_invitation()
        .times(1)
        .withf(move |uid, cid| *uid == ids.user_id && *cid == community_id)
        .returning(|_, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/invitations/community/{community_id}/accept"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_accept_community_team_invitation_keeps_selected_community() {
    // Setup identifiers of a session that already selected a community
    let community_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock without the first community and group selection
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_accept_community_team_invitation()
        .times(1)
        .withf(move |uid, cid| *uid == ids.user_id && *cid == community_id)
        .returning(|_, _| Ok(()));
    db.expect_list_user_groups().never();
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && message_matches(record, "Team invitation accepted.")
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(ids.community_id))
                && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/invitations/community/{community_id}/accept"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_accept_event_admission_offer_route_is_removed() {
    // Setup a request for the deleted route
    let admission_offer_id = Uuid::new_v4();

    // Setup the not-found page database expectation
    let mut db = MockDB::new();
    expect_site_settings(&mut db);

    // Send the former route through the application router
    let router = TestRouterBuilder::new(db).build().await;
    let request = request(
        "PUT",
        &format!("/dashboard/user/invitations/event-offers/{admission_offer_id}/accept"),
    )
    .body(Body::empty())
    .unwrap();
    let (parts, bytes) = send(router, request).await;

    // Check the removed route stays unavailable
    assert_html_response(&parts, &bytes, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn test_accept_group_team_invitation_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();
    let groups = sample_user_groups_by_community(community_id, group_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_accept_group_team_invitation()
        .times(1)
        .withf(move |uid, gid| *uid == ids.user_id && *gid == group_id)
        .returning(|_, _| Ok(()));
    db.expect_list_user_groups()
        .times(1)
        .withf(move |uid| *uid == ids.user_id)
        .returning(move |_| Ok(groups.clone()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
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

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/invitations/group/{group_id}/accept"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_accept_group_team_invitation_keeps_selected_community() {
    // Setup identifiers of a session that already selected a community
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock without the first community and group selection
    let mut db = MockDB::new();
    expect_community_session(&mut db, &ids);
    db.expect_accept_group_team_invitation()
        .times(1)
        .withf(move |uid, gid| *uid == ids.user_id && *gid == group_id)
        .returning(|_, _| Ok(()));
    db.expect_list_user_groups().never();
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id
                && message_matches(record, "Team invitation accepted.")
                && record
                    .data
                    .get(SELECTED_COMMUNITY_ID_KEY)
                    .is_some_and(|value| value == &json!(ids.community_id))
                && !record.data.contains_key(SELECTED_GROUP_ID_KEY)
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/invitations/group/{group_id}/accept"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_decline_event_admission_offer_success() {
    // Setup identifiers and data structures
    let admission_offer_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_decline_event_admission_offer()
        .times(1)
        .withf(move |uid, oid, provider| {
            *uid == ids.user_id
                && *oid == admission_offer_id
                && *provider == Some(crate::types::payments::PaymentProvider::Stripe)
        })
        .returning(move |_, _, _| {
            Ok(EventEnrollmentReconciliationOutcome {
                community_id: Uuid::from_u128(1),
                event_id: Uuid::from_u128(2),
                group_id: Uuid::from_u128(3),
            })
        });
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Event offer declined.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db)
        .with_payments_cfg(sample_payments_cfg())
        .build()
        .await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/invitations/event-offers/{admission_offer_id}/decline"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_reject_community_team_invitation_success() {
    // Setup identifiers and data structures
    let community_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_reject_community_team_invitation()
        .times(1)
        .withf(move |uid, cid| *uid == ids.user_id && *cid == community_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Team invitation rejected.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/invitations/community/{community_id}/reject"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_reject_group_team_invitation_success() {
    // Setup identifiers and data structures
    let group_id = Uuid::new_v4();
    let ids = DashboardIds::new();

    // Setup database mock
    let mut db = MockDB::new();
    expect_session(&mut db, &ids);
    db.expect_reject_group_team_invitation()
        .times(1)
        .withf(move |uid, gid| *uid == ids.user_id && *gid == group_id)
        .returning(|_, _| Ok(()));
    db.expect_update_session()
        .times(1)
        .withf(move |record| {
            record.id == ids.session_id && message_matches(record, "Team invitation rejected.")
        })
        .returning(|_| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = empty_request(
        "PUT",
        &format!("/dashboard/user/invitations/group/{group_id}/reject"),
        ids.session_id,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}
