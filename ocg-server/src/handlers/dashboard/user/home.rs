//! HTTP handlers for the user dashboard.

use std::collections::HashMap;

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Query, RawQuery, State},
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::error::HandlerError,
    router::serde_qs_config,
    templates::{
        PageId,
        auth::{self, User, UserDetails},
        dashboard::user::{
            home::{Content, Page, Tab},
            invitations, session_proposals, submissions,
        },
        pagination::NavigationLinks,
    },
};

/// Handler that returns the user dashboard home page.
///
/// This handler manages the main user dashboard page, selecting the appropriate tab
/// and preparing the content for each dashboard section.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    messages: Messages,
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Get user from session (endpoint is behind login_required)
    let user = auth_session.user.as_ref().expect("user to be logged in").clone();

    // Get selected tab from query
    let raw_query = raw_query.as_deref().unwrap_or_default();
    let tab: Tab = query.get("tab").unwrap_or(&String::new()).parse().unwrap_or_default();

    // Get site settings
    let site_settings = db.get_site_settings().await?;

    // Prepare content for the selected tab
    let content = match tab {
        Tab::Account => {
            let timezones = db.list_timezones().await?;
            Content::Account(Box::new(auth::UpdateUserPage {
                has_password: user.has_password.unwrap_or(false),
                timezones,
                user: UserDetails::from(user),
            }))
        }
        Tab::Invitations => {
            let (community_invitations, group_invitations) = tokio::try_join!(
                db.list_user_community_team_invitations(user.user_id),
                db.list_user_group_team_invitations(user.user_id)
            )?;
            Content::Invitations(invitations::ListPage {
                community_invitations,
                group_invitations,
            })
        }
        Tab::SessionProposals => {
            let filters: session_proposals::SessionProposalsFilters =
                serde_qs_config().deserialize_str(raw_query)?;
            let (session_proposal_levels, session_proposals_output) = tokio::try_join!(
                db.list_session_proposal_levels(),
                db.list_user_session_proposals(user.user_id, &filters)
            )?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                session_proposals_output.total,
                "/dashboard/user?tab=session-proposals",
                "/dashboard/user/session-proposals",
            )?;
            Content::SessionProposals(session_proposals::ListPage {
                session_proposal_levels,
                session_proposals: session_proposals_output.session_proposals,
                navigation_links,
                total: session_proposals_output.total,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
        Tab::Submissions => {
            let filters: submissions::CfsSubmissionsFilters = serde_qs_config().deserialize_str(raw_query)?;
            let submissions = db.list_user_cfs_submissions(user.user_id, &filters).await?;
            let navigation_links = NavigationLinks::from_filters(
                &filters,
                submissions.total,
                "/dashboard/user?tab=submissions",
                "/dashboard/user/submissions",
            )?;
            Content::Submissions(submissions::ListPage {
                submissions: submissions.submissions,
                navigation_links,
                total: submissions.total,
                limit: filters.limit,
                offset: filters.offset,
            })
        }
    };

    // Render the page
    let page = Page {
        content,
        messages: messages.into_iter().collect(),
        page_id: PageId::UserDashboard,
        path: "/dashboard/user".to_string(),
        site_settings,
        user: User::from_session(auth_session).await?,
    };

    let html = Html(page.render()?);
    Ok(html)
}

// Tests.

#[cfg(test)]
mod tests {
    use anyhow::anyhow;
    use axum::{
        body::{Body, to_bytes},
        http::{
            HeaderValue, Request, StatusCode,
            header::{CACHE_CONTROL, CONTENT_TYPE, COOKIE},
        },
    };
    use axum_login::tower_sessions::session;
    use tower::ServiceExt;
    use uuid::Uuid;

    use crate::{
        db::mock::MockDB, handlers::tests::*, router::CACHE_CONTROL_NO_CACHE,
        services::notifications::MockNotificationsManager,
    };

    #[tokio::test]
    async fn test_page_account_tab_success() {
        // Setup identifiers and data structures
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
        db.expect_list_timezones()
            .times(1)
            .returning(|| Ok(vec!["UTC".to_string(), "America/New_York".to_string()]));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8"),
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_page_invitations_tab_success() {
        // Setup identifiers and data structures
        let community_id = Uuid::new_v4();
        let session_id = session::Id::default();
        let user_id = Uuid::new_v4();
        let group_id = Uuid::new_v4();
        let auth_hash = "hash".to_string();
        let session_record = sample_session_record(session_id, user_id, &auth_hash, None, None);
        let community_invitations = vec![sample_community_invitation(community_id)];
        let group_invitations = vec![sample_group_invitation(group_id)];

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
        db.expect_list_user_group_team_invitations()
            .times(1)
            .withf(move |uid| *uid == user_id)
            .returning(move |_| Ok(group_invitations.clone()));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Ok(sample_site_settings()));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user?tab=invitations")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::OK);
        assert_eq!(
            parts.headers.get(CONTENT_TYPE).unwrap(),
            &HeaderValue::from_static("text/html; charset=utf-8"),
        );
        assert_eq!(
            parts.headers.get(CACHE_CONTROL).unwrap(),
            &HeaderValue::from_static(CACHE_CONTROL_NO_CACHE),
        );
        assert!(!bytes.is_empty());
    }

    #[tokio::test]
    async fn test_page_db_error() {
        // Setup identifiers and data structures
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
        let auth_hash_for_user = auth_hash.clone();
        db.expect_get_user_by_id()
            .times(1)
            .withf(move |id| *id == user_id)
            .returning(move |_| Ok(Some(sample_auth_user(user_id, &auth_hash_for_user))));
        db.expect_get_site_settings()
            .times(1)
            .returning(|| Err(anyhow!("db error")));

        // Setup notifications manager mock
        let nm = MockNotificationsManager::new();

        // Setup router and send request
        let router = TestRouterBuilder::new(db, nm).build().await;
        let request = Request::builder()
            .method("GET")
            .uri("/dashboard/user")
            .header(COOKIE, format!("id={session_id}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let bytes = to_bytes(body, usize::MAX).await.unwrap();

        // Check response matches expectations
        assert_eq!(parts.status, StatusCode::INTERNAL_SERVER_ERROR);
        assert!(bytes.is_empty());
    }
}
