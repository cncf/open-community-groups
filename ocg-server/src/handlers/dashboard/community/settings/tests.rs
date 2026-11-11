use axum::http::StatusCode;

use crate::{
    db::mock::MockDB,
    handlers::{error::INVALID_REQUEST_PAYLOAD, tests::*},
    test_util::opening_tag_with,
    types::{community::CommunityFull, permissions::CommunityPermission},
};

#[tokio::test]
async fn test_update_page_success() {
    // Setup identifiers and data structures
    let ids = DashboardIds::new();
    let community = CommunityFull {
        banner_dark_url: Some("https://example.test/community-banner-dark.png".to_string()),
        banner_mobile_dark_url: Some(
            "https://example.test/community-banner-mobile-dark.png".to_string(),
        ),
        logo_dark_url: Some("https://example.test/community-logo-dark.png".to_string()),
        ..sample_community_full(ids.community_id)
    };

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

    // Check the dark images are rendered in the form with their upload targets
    assert_image_field_value(
        html,
        "banner_dark_url",
        "https://example.test/community-banner-dark.png",
    );
    assert_image_field_value(
        html,
        "banner_mobile_dark_url",
        "https://example.test/community-banner-mobile-dark.png",
    );
    assert_image_field_value(
        html,
        "logo_dark_url",
        "https://example.test/community-logo-dark.png",
    );
    for (name, target) in [
        ("banner_dark_url", "banner"),
        ("banner_mobile_dark_url", "banner_mobile"),
        ("logo_dark_url", "logo"),
    ] {
        let field = opening_tag_with(html, &format!(r#"name="{name}""#));
        assert!(field.contains(&format!(r#"target="{target}""#)), "{name}");
    }
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
