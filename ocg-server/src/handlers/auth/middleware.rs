//! This module defines the authorization middleware that guards the
//! dashboard routes, together with the redirect responses it produces for
//! page, HTMX, and OCG fetch requests.

use axum::{
    extract::{Path, Request, State},
    http::{HeaderMap, StatusCode},
    middleware::Next,
    response::{IntoResponse, Redirect, Response},
};
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{
        auth::{
            LOG_IN_URL,
            session_context::{
                SELECTED_COMMUNITY_ID_KEY, resolve_community_dashboard_context,
                resolve_group_dashboard_context,
            },
        },
        error::HandlerError,
        extractors::{SelectedCommunityId, SelectedGroupId},
    },
    types::permissions::{CommunityPermission, GroupPermission},
};

#[cfg(test)]
mod tests;

/// URL for user dashboard invitations tab.
pub(crate) const USER_DASHBOARD_INVITATIONS_URL: &str = "/dashboard/user?tab=invitations";

// Authorization middleware.

/// Ensures the user can enter the community dashboard, falling back to the
/// first accessible community when the selected one is no longer available.
#[instrument(skip_all)]
pub(crate) async fn user_has_community_dashboard_permission(
    State(db): State<DynDB>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user_id) = auth_session.user.as_ref().map(|user| user.user_id) else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve readable community context, repairing stale session state when possible
    let community_id = match resolve_community_dashboard_context(
        &db,
        &session,
        &user_id,
        CommunityPermission::Read,
    )
    .await
    {
        Ok(Some(community_id)) => community_id,
        Ok(None) => return redirect_to_invitations_for_request(request.headers()),
        Err(error) => return error.into_response(),
    };

    // Store selected community context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));

    next.run(request).await.into_response()
}

/// Check if the user has a specific community permission in a path community.
#[instrument(skip_all)]
pub(crate) async fn user_has_path_community_permission(
    State((db, permission)): State<(DynDB, CommunityPermission)>,
    Path(community_id): Path<Uuid>,
    auth_session: AuthSession,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Check required permission against the community id from the path
    let Ok(has_permission) = db
        .user_has_community_permission(&community_id, &user.user_id, permission)
        .await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !has_permission {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user has a specific group permission in a path group.
#[instrument(skip_all)]
pub(crate) async fn user_has_path_group_permission(
    State((db, permission)): State<(DynDB, GroupPermission)>,
    Path(group_id): Path<Uuid>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user) = auth_session.user else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve selected community to evaluate group permission in that context
    let community_id = match session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await {
        Ok(Some(community_id)) => community_id,
        Ok(None) => return redirect_to_invitations_for_request(request.headers()),
        Err(error) => return HandlerError::Session(error).into_response(),
    };

    // Ensure the path group belongs to the selected community before checking permissions
    let Ok(group_belongs_to_community) =
        db.group_belongs_to_community(&community_id, &group_id).await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !group_belongs_to_community {
        return StatusCode::FORBIDDEN.into_response();
    }

    // Check required permission against the group id from the path
    let Ok(has_permission) = db
        .user_has_group_permission(&community_id, &group_id, &user.user_id, permission)
        .await
    else {
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };
    if !has_permission {
        return StatusCode::FORBIDDEN.into_response();
    }

    next.run(request).await.into_response()
}

/// Check if the user has a specific community permission in the selected
/// community.
#[instrument(skip_all)]
pub(crate) async fn user_has_selected_community_permission(
    State((db, permission)): State<(DynDB, CommunityPermission)>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user_id) = auth_session.user.as_ref().map(|user| user.user_id) else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve readable community context, repairing stale session state when possible
    let community_id =
        match resolve_community_dashboard_context(&db, &session, &user_id, permission).await {
            Ok(Some(community_id)) => community_id,
            Ok(None) => return redirect_to_invitations_for_request(request.headers()),
            Err(error) => return error.into_response(),
        };

    // Store selected community context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));

    next.run(request).await.into_response()
}

/// Check if the user has a specific group permission in the selected group.
#[instrument(skip_all)]
pub(crate) async fn user_has_selected_group_permission(
    State((db, permission)): State<(DynDB, GroupPermission)>,
    auth_session: AuthSession,
    session: Session,
    request: Request,
    next: Next,
) -> impl IntoResponse {
    // Require an authenticated user
    let Some(user_id) = auth_session.user.as_ref().map(|user| user.user_id) else {
        return StatusCode::FORBIDDEN.into_response();
    };

    // Resolve readable group context, repairing stale session state when possible
    let (community_id, group_id) =
        match resolve_group_dashboard_context(&db, &session, &user_id, permission).await {
            Ok(Some(ids)) => ids,
            Ok(None) => return redirect_to_invitations_for_request(request.headers()),
            Err(error) => return error.into_response(),
        };

    // Store selected community and group context for downstream extractors
    let mut request = request;
    request.extensions_mut().insert(SelectedCommunityId(community_id));
    request.extensions_mut().insert(SelectedGroupId(group_id));

    next.run(request).await.into_response()
}

// Helpers.

/// Logs out the user after detecting a stale dashboard selection.
pub(crate) async fn log_out_for_stale_dashboard_context(
    auth_session: &mut AuthSession,
    headers: &HeaderMap,
) -> Result<Response, HandlerError> {
    auth_session.logout().await.map_err(|_| HandlerError::Auth)?;

    Ok(redirect_to_log_in_for_request(headers))
}

/// Returns whether the request came from HTMX.
fn is_htmx_request(headers: &HeaderMap) -> bool {
    headers
        .get("HX-Request")
        .is_some_and(|value| value.as_bytes().eq_ignore_ascii_case(b"true"))
}

/// Returns whether the request came from an OCG fetch helper.
fn is_ocg_fetch_request(headers: &HeaderMap) -> bool {
    headers
        .get("X-OCG-Fetch")
        .is_some_and(|value| value.as_bytes().eq_ignore_ascii_case(b"true"))
}

/// Builds the invitations redirect response expected by the request type.
fn redirect_to_invitations_for_request(headers: &HeaderMap) -> Response {
    // HTMX follows redirect headers without swapping the user dashboard into a fragment
    if is_htmx_request(headers) {
        return (
            StatusCode::OK,
            [("HX-Redirect", USER_DASHBOARD_INVITATIONS_URL)],
        )
            .into_response();
    }

    // OCG fetch helpers use redirect metadata instead of following a fetch redirect
    if is_ocg_fetch_request(headers) {
        return (
            StatusCode::OK,
            [("X-OCG-Redirect", USER_DASHBOARD_INVITATIONS_URL)],
        )
            .into_response();
    }

    // Normal page requests can use a standard redirect response
    Redirect::to(USER_DASHBOARD_INVITATIONS_URL).into_response()
}

/// Builds the log-in redirect response expected by the request type.
fn redirect_to_log_in_for_request(headers: &HeaderMap) -> Response {
    // HTMX follows redirects from response headers when swapping fragments
    if is_htmx_request(headers) {
        return (StatusCode::OK, [("HX-Redirect", LOG_IN_URL)]).into_response();
    }

    // OCG fetch helpers use redirect metadata for browser navigation
    if is_ocg_fetch_request(headers) {
        return (StatusCode::UNAUTHORIZED, [("X-OCG-Redirect", LOG_IN_URL)]).into_response();
    }

    // Normal page requests can use a standard redirect response
    Redirect::to(LOG_IN_URL).into_response()
}
