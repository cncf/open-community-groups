//! Versioned JSON API router.

use axum::{
    Router,
    routing::{delete, get, patch, post},
};

use crate::handlers::api::{admin, public, tokens, user};

use super::State;

/// Sets up `/api/v1` routes.
pub(super) fn setup_api_router() -> Router<State> {
    Router::new()
        .route("/health", get(public::health))
        .route("/meta/filters", get(public::filters))
        .route(
            "/alliances",
            get(public::alliances).post(admin::create_alliance),
        )
        .route(
            "/alliances/{alliance}",
            get(public::alliance).patch(admin::update_alliance),
        )
        .route(
            "/alliances/{alliance}/groups",
            get(public::alliance_groups).post(admin::create_group),
        )
        .route(
            "/alliances/{alliance}/groups/{group_id}",
            patch(admin::update_group),
        )
        .route("/alliances/{alliance}/events", get(public::alliance_events))
        .route("/groups/{alliance}/{group_slug}", get(public::group))
        .route(
            "/groups/{alliance}/{group_id}/join",
            post(user::join_group).delete(user::leave_group),
        )
        .route("/groups/{group_id}/events", post(admin::create_event))
        .route(
            "/events/{alliance}/{group_slug}/{event_slug}",
            get(public::event),
        )
        .route(
            "/events/{alliance}/{event_id}/attendance",
            get(user::event_attendance),
        )
        .route(
            "/events/{alliance}/{event_id}/attend",
            post(user::attend_event).delete(user::leave_event),
        )
        .route("/events/{event_id}", patch(admin::update_event))
        .route("/jobs", get(public::jobs).post(admin::create_job))
        .route("/jobs/{slug}", get(public::job))
        .route(
            "/jobs/id/{job_id}",
            patch(admin::update_job).delete(admin::delete_job),
        )
        .route("/jobs/{job_id}/applications", post(user::apply_to_job))
        .route(
            "/landscape",
            get(public::landscape).post(admin::create_landscape_entry),
        )
        .route(
            "/landscape/{entry_id}",
            patch(admin::update_landscape_entry),
        )
        .route("/search", get(public::search))
        .route("/me", get(user::me).patch(user::update_me))
        .route("/me/tokens", get(tokens::list).post(tokens::create))
        .route("/me/tokens/{token_id}", delete(tokens::revoke))
}
