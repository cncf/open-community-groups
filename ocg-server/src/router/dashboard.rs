//! Dashboard router setup for the OCG server.
//!
//! This module configures the community, group, and user dashboard sub-routers
//! with their respective permission-based middleware layers.

use axum::{
    Router, middleware,
    routing::{delete, get, post, put},
};

use crate::{
    handlers::{auth, dashboard, dashboard::common},
    types::permissions::{CommunityPermission, GroupPermission},
};

use super::State;

/// Sets up the community dashboard router and its routes.
#[allow(clippy::too_many_lines)]
pub(super) fn setup_community_dashboard_router(state: &State) -> Router<State> {
    // Setup authorization middleware helpers
    let check_path_community_permission = |permission| {
        middleware::from_fn_with_state(
            (state.db.clone(), permission),
            auth::user_has_path_community_permission,
        )
    };
    let check_selected_community_permission = |permission| {
        middleware::from_fn_with_state(
            (state.db.clone(), permission),
            auth::user_has_selected_community_permission,
        )
    };
    let check_community_dashboard_permission =
        || middleware::from_fn_with_state(state.db.clone(), auth::user_has_community_dashboard_permission);

    // Read-only community dashboard endpoints
    let dashboard_read = Router::new()
        .route("/analytics", get(dashboard::community::analytics::page))
        .route(
            "/event-categories",
            get(dashboard::community::event_categories::list_page),
        )
        .route(
            "/event-categories/add",
            get(dashboard::community::event_categories::add_page),
        )
        .route(
            "/event-categories/{event_category_id}/update",
            get(dashboard::community::event_categories::update_page),
        )
        .route(
            "/group-categories",
            get(dashboard::community::group_categories::list_page),
        )
        .route(
            "/group-categories/add",
            get(dashboard::community::group_categories::add_page),
        )
        .route(
            "/group-categories/{group_category_id}/update",
            get(dashboard::community::group_categories::update_page),
        )
        .route("/groups", get(dashboard::community::groups::list_page))
        .route("/groups/add", get(dashboard::community::groups::add_page))
        .route(
            "/groups/{group_id}/update",
            get(dashboard::community::groups::update_page),
        )
        .route("/logs", get(dashboard::community::logs::list_page))
        .route(
            "/settings/update",
            get(dashboard::community::settings::update_page),
        )
        .route("/team", get(dashboard::community::team::list_page))
        .route("/regions", get(dashboard::community::regions::list_page))
        .route("/regions/add", get(dashboard::community::regions::add_page))
        .route(
            "/regions/{region_id}/update",
            get(dashboard::community::regions::update_page),
        )
        .route_layer(check_selected_community_permission(CommunityPermission::Read));

    // Community groups management endpoints
    let groups_management = Router::new()
        .route("/groups/add", post(dashboard::community::groups::add))
        .route(
            "/groups/{group_id}/activate",
            put(dashboard::community::groups::activate),
        )
        .route(
            "/groups/{group_id}/deactivate",
            put(dashboard::community::groups::deactivate),
        )
        .route(
            "/groups/{group_id}/delete",
            delete(dashboard::community::groups::delete),
        )
        .route(
            "/groups/{group_id}/update",
            put(dashboard::community::groups::update),
        )
        .route_layer(check_selected_community_permission(
            CommunityPermission::GroupsWrite,
        ));

    // Community settings management endpoints
    let settings_management = Router::new()
        .route("/settings/update", put(dashboard::community::settings::update))
        .route_layer(check_selected_community_permission(
            CommunityPermission::SettingsWrite,
        ));

    // Community taxonomy management endpoints
    let taxonomy_management = Router::new()
        .route(
            "/event-categories/add",
            post(dashboard::community::event_categories::add),
        )
        .route(
            "/event-categories/{event_category_id}/delete",
            delete(dashboard::community::event_categories::delete),
        )
        .route(
            "/event-categories/{event_category_id}/update",
            put(dashboard::community::event_categories::update),
        )
        .route(
            "/group-categories/add",
            post(dashboard::community::group_categories::add),
        )
        .route(
            "/group-categories/{group_category_id}/delete",
            delete(dashboard::community::group_categories::delete),
        )
        .route(
            "/group-categories/{group_category_id}/update",
            put(dashboard::community::group_categories::update),
        )
        .route("/regions/add", post(dashboard::community::regions::add))
        .route(
            "/regions/{region_id}/delete",
            delete(dashboard::community::regions::delete),
        )
        .route(
            "/regions/{region_id}/update",
            put(dashboard::community::regions::update),
        )
        .route_layer(check_selected_community_permission(
            CommunityPermission::TaxonomyWrite,
        ));

    // Community team management endpoints
    let team_management = Router::new()
        .route("/team/add", post(dashboard::community::team::add))
        .route(
            "/team/{user_id}/delete",
            delete(dashboard::community::team::delete),
        )
        .route(
            "/team/{user_id}/role",
            put(dashboard::community::team::update_role),
        )
        .route("/users/search", get(common::search_user))
        .route_layer(check_selected_community_permission(
            CommunityPermission::TeamWrite,
        ));

    // Setup router
    Router::new()
        .route(
            "/",
            get(dashboard::community::home::page).route_layer(check_community_dashboard_permission()),
        )
        .merge(dashboard_read)
        .merge(groups_management)
        .merge(settings_management)
        .merge(taxonomy_management)
        .merge(team_management)
        .route(
            "/{community_id}/select",
            put(dashboard::community::select_community)
                .route_layer(check_path_community_permission(CommunityPermission::Read)),
        )
}

/// Sets up the group dashboard router and its routes.
#[allow(clippy::too_many_lines)]
pub(super) fn setup_group_dashboard_router(state: &State) -> Router<State> {
    // Setup authorization middleware helpers
    let check_path_group_permission = |permission| {
        middleware::from_fn_with_state(
            (state.db.clone(), permission),
            auth::user_has_path_group_permission,
        )
    };
    let check_selected_group_permission = |permission| {
        middleware::from_fn_with_state(
            (state.db.clone(), permission),
            auth::user_has_selected_group_permission,
        )
    };

    // Setup permission-bucket subrouters

    // Read-only group dashboard endpoints
    let dashboard_read = Router::new()
        .route("/", get(dashboard::group::home::page))
        .route("/analytics", get(dashboard::group::analytics::page))
        .route(
            "/check-in/{event_id}/qr-code",
            get(dashboard::group::attendees::generate_check_in_qr_code),
        )
        .route("/events", get(dashboard::group::events::list_page))
        .route("/events/add", get(dashboard::group::events::add_page))
        .route(
            "/events/{event_id}/attendees",
            get(dashboard::group::attendees::list_page),
        )
        .route(
            "/events/{event_id}/attendees.csv",
            get(dashboard::group::attendees::download_csv),
        )
        .route(
            "/events/{event_id}/invitation-requests",
            get(dashboard::group::invitation_requests::list_page),
        )
        .route(
            "/events/{event_id}/details",
            get(dashboard::group::events::details),
        )
        .route(
            "/events/{event_id}/submissions",
            get(dashboard::group::submissions::list_page),
        )
        .route(
            "/events/{event_id}/update",
            get(dashboard::group::events::update_page),
        )
        .route(
            "/events/{event_id}/waitlist",
            get(dashboard::group::waitlist::list_page),
        )
        .route("/logs", get(dashboard::group::logs::list_page))
        .route("/members", get(dashboard::group::members::list_page))
        .route("/settings/update", get(dashboard::group::settings::update_page))
        .route("/sponsors", get(dashboard::group::sponsors::list_page))
        .route("/sponsors/add", get(dashboard::group::sponsors::add_page))
        .route(
            "/sponsors/{group_sponsor_id}/update",
            get(dashboard::group::sponsors::update_page),
        )
        .route("/team", get(dashboard::group::team::list_page))
        .route_layer(check_selected_group_permission(GroupPermission::Read));

    // Group events management endpoints
    let events_management = Router::new()
        .route("/events/add", post(dashboard::group::events::add))
        .route("/events/preview", post(dashboard::group::events::preview))
        .route(
            "/events/{event_id}/attendees/{user_id}/check-in",
            post(dashboard::group::attendees::manual_check_in),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/invitation/accept",
            put(dashboard::group::attendees::accept_invitation_request),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/invitation/reject",
            put(dashboard::group::attendees::reject_invitation_request),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/refund/approve",
            put(dashboard::group::attendees::approve_refund_request),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/refund/reject",
            put(dashboard::group::attendees::reject_refund_request),
        )
        .route("/events/{event_id}/cancel", put(dashboard::group::events::cancel))
        .route(
            "/events/{event_id}/delete",
            delete(dashboard::group::events::delete),
        )
        .route(
            "/events/{event_id}/publish",
            put(dashboard::group::events::publish),
        )
        .route(
            "/events/{event_id}/submissions/{cfs_submission_id}",
            put(dashboard::group::submissions::update),
        )
        .route(
            "/events/{event_id}/unpublish",
            put(dashboard::group::events::unpublish),
        )
        .route("/events/{event_id}/update", put(dashboard::group::events::update))
        .route(
            "/notifications/{event_id}",
            post(dashboard::group::attendees::send_event_custom_notification),
        )
        .route("/users/search", get(common::search_user))
        .route_layer(check_selected_group_permission(GroupPermission::EventsWrite));

    // Group member management endpoints
    let members_management = Router::new()
        .route(
            "/notifications",
            post(dashboard::group::members::send_group_custom_notification),
        )
        .route_layer(check_selected_group_permission(GroupPermission::MembersWrite));

    // Group settings management endpoints
    let settings_management = Router::new()
        .route("/settings/update", put(dashboard::group::settings::update))
        .route_layer(check_selected_group_permission(GroupPermission::SettingsWrite));

    // Group sponsor management endpoints
    let sponsors_management = Router::new()
        .route("/sponsors/add", post(dashboard::group::sponsors::add))
        .route(
            "/sponsors/{group_sponsor_id}/delete",
            delete(dashboard::group::sponsors::delete),
        )
        .route(
            "/sponsors/{group_sponsor_id}/featured",
            put(dashboard::group::sponsors::update_featured),
        )
        .route(
            "/sponsors/{group_sponsor_id}/update",
            put(dashboard::group::sponsors::update),
        )
        .route_layer(check_selected_group_permission(GroupPermission::SponsorsWrite));

    // Group team management endpoints
    let team_management = Router::new()
        .route("/team/add", post(dashboard::group::team::add))
        .route("/team/{user_id}/delete", delete(dashboard::group::team::delete))
        .route("/team/{user_id}/role", put(dashboard::group::team::update_role))
        .route_layer(check_selected_group_permission(GroupPermission::TeamWrite));

    // Setup router
    Router::new()
        .merge(dashboard_read)
        .merge(events_management)
        .merge(members_management)
        .merge(settings_management)
        .merge(sponsors_management)
        .merge(team_management)
        .route(
            "/{group_id}/select",
            put(dashboard::group::select_group)
                .route_layer(check_path_group_permission(GroupPermission::Read)),
        )
        .route(
            "/community/{community_id}/select",
            put(dashboard::group::select_community),
        )
}

/// Sets up the user dashboard router and its routes.
pub(super) fn setup_user_dashboard_router() -> Router<State> {
    // Setup router
    Router::new()
        .route("/", get(dashboard::user::home::page))
        .route("/events", get(dashboard::user::events::list_page))
        .route("/invitations", get(dashboard::user::invitations::list_page))
        .route(
            "/invitations/community/{community_id}/accept",
            put(dashboard::user::invitations::accept_community_team_invitation),
        )
        .route(
            "/invitations/community/{community_id}/reject",
            put(dashboard::user::invitations::reject_community_team_invitation),
        )
        .route(
            "/invitations/group/{group_id}/accept",
            put(dashboard::user::invitations::accept_group_team_invitation),
        )
        .route(
            "/invitations/group/{group_id}/reject",
            put(dashboard::user::invitations::reject_group_team_invitation),
        )
        .route("/logs", get(dashboard::user::logs::list_page))
        .route(
            "/session-proposals",
            get(dashboard::user::session_proposals::list_page).post(dashboard::user::session_proposals::add),
        )
        .route(
            "/session-proposals/{session_proposal_id}",
            put(dashboard::user::session_proposals::update)
                .delete(dashboard::user::session_proposals::delete),
        )
        .route(
            "/session-proposals/{session_proposal_id}/co-speaker-invitation/accept",
            put(dashboard::user::session_proposals::accept_co_speaker_invitation),
        )
        .route(
            "/session-proposals/{session_proposal_id}/co-speaker-invitation/reject",
            put(dashboard::user::session_proposals::reject_co_speaker_invitation),
        )
        .route("/submissions", get(dashboard::user::submissions::list_page))
        .route(
            "/submissions/{cfs_submission_id}/resubmit",
            put(dashboard::user::submissions::resubmit),
        )
        .route(
            "/submissions/{cfs_submission_id}/withdraw",
            put(dashboard::user::submissions::withdraw),
        )
        .route("/users/search", get(common::search_user))
}
