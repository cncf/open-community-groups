use axum::http::StatusCode;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    types::permissions::CommunityPermission,
};

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let community = sample_community_full(ids.community_id);

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::Read);
    expect_community_permission_result(&mut db, &ids, CommunityPermission::SettingsWrite, true);
    db.expect_get_community_full()
        .times(1)
        .withf(move |community_id| *community_id == ids.community_id)
        .returning(move |_| Ok(community.clone()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = get_request("/dashboard/community/settings/update", ids.session_id);
    let (parts, bytes) = send(router, request).await;

    // Check the editable form is rendered
    assert_html_response(&parts, &bytes, StatusCode::OK);
    let html = std::str::from_utf8(&bytes).unwrap();
    assert!(!html.contains("Your role cannot update community settings."));

    // Check image fields render target sizes and validated upload targets
    let logo_field = html
        .split(r#"name="logo_url""#)
        .nth(1)
        .and_then(|rest| rest.split('>').next())
        .unwrap();
    assert!(logo_field.contains(r#"target="logo""#));
    assert!(!logo_field.contains("help-prefix-text"));
    assert!(html.contains(r#"help-prefix-text="Size required 2400 x 300 px." target="ad_banner""#));
    assert!(html.contains(
        r#"help-prefix-text="Size required 1200 x 630 px. Format must be PNG, JPEG, or WebP." target="open_graph""#
    ));
}

#[tokio::test]
async fn test_update_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let update = sample_community_update();
    let expected_display_name = update.display_name.clone();
    let body = serde_qs::to_string(&update).unwrap();

    // Setup database mock
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::SettingsWrite);
    db.expect_update_community()
        .times(1)
        .withf(move |user_id, community_id, update| {
            *user_id == ids.user_id
                && *community_id == ids.community_id
                && update.display_name == expected_display_name
        })
        .returning(|_, _, _| Ok(()));

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        "/dashboard/community/settings/update",
        ids.session_id,
        body,
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_empty_hx_trigger_response(&parts, &bytes, StatusCode::NO_CONTENT, "refresh-body");
}

#[tokio::test]
async fn test_update_invalid_payload() {
    // Setup identifiers and database mock
    let ids = DashboardIds::new();
    let mut db = MockDB::new();
    expect_community_access(&mut db, &ids, CommunityPermission::SettingsWrite);

    // Setup router and send request
    let router = TestRouterBuilder::new(db).build().await;
    let request = form_request(
        "PUT",
        "/dashboard/community/settings/update",
        ids.session_id,
        "invalid-body",
    );
    let (parts, bytes) = send(router, request).await;

    // Check response matches expectations
    assert_eq!(parts.status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(bytes.as_ref(), INVALID_REQUEST_PAYLOAD.as_bytes());
}
