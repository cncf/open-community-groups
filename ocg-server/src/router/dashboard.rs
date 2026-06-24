//! Dashboard router setup for the OCG server.
//!
//! This module configures the alliance, group, and user dashboard sub-routers
//! with their respective permission-based middleware layers.

use axum::{
    Router, middleware,
    routing::{delete, get, post, put},
};

use crate::{
    handlers::{auth, dashboard, dashboard::common},
    types::permissions::{AlliancePermission, GroupPermission},
};

use super::State;

/// Sets up the alliance dashboard router and its routes.
#[allow(clippy::too_many_lines)]
pub(super) fn setup_alliance_dashboard_router(state: &State) -> Router<State> {
    // Setup authorization middleware helpers
    let check_path_alliance_permission = |permission| {
        middleware::from_fn_with_state(
            (state.db.clone(), permission),
            auth::user_has_path_alliance_permission,
        )
    };
    let check_selected_alliance_permission = |permission| {
        middleware::from_fn_with_state(
            (state.db.clone(), permission),
            auth::user_has_selected_alliance_permission,
        )
    };
    let check_alliance_dashboard_permission = || {
        middleware::from_fn_with_state(
            state.db.clone(),
            auth::user_has_alliance_dashboard_permission,
        )
    };

    // Read-only alliance dashboard endpoints
    let dashboard_read = Router::new()
        .route("/analytics", get(dashboard::alliance::analytics::page))
        .route(
            "/event-categories",
            get(dashboard::alliance::event_categories::list_page),
        )
        .route(
            "/event-categories/add",
            get(dashboard::alliance::event_categories::add_page),
        )
        .route(
            "/event-categories/{event_category_id}/update",
            get(dashboard::alliance::event_categories::update_page),
        )
        .route(
            "/group-categories",
            get(dashboard::alliance::group_categories::list_page),
        )
        .route(
            "/group-categories/add",
            get(dashboard::alliance::group_categories::add_page),
        )
        .route(
            "/group-categories/{group_category_id}/update",
            get(dashboard::alliance::group_categories::update_page),
        )
        .route("/groups", get(dashboard::alliance::groups::list_page))
        .route("/groups/add", get(dashboard::alliance::groups::add_page))
        .route(
            "/groups/{group_id}/update",
            get(dashboard::alliance::groups::update_page),
        )
        .route("/landscape", get(dashboard::alliance::landscape::list_page))
        .route("/logs", get(dashboard::alliance::logs::list_page))
        .route(
            "/settings/update",
            get(dashboard::alliance::settings::update_page),
        )
        .route("/team", get(dashboard::alliance::team::list_page))
        .route("/regions", get(dashboard::alliance::regions::list_page))
        .route("/regions/add", get(dashboard::alliance::regions::add_page))
        .route(
            "/regions/{region_id}/update",
            get(dashboard::alliance::regions::update_page),
        )
        .route_layer(check_selected_alliance_permission(AlliancePermission::Read));

    // Alliance groups management endpoints
    let groups_management = Router::new()
        .route("/groups/add", post(dashboard::alliance::groups::add))
        .route(
            "/groups/{group_id}/activate",
            put(dashboard::alliance::groups::activate),
        )
        .route(
            "/groups/{group_id}/deactivate",
            put(dashboard::alliance::groups::deactivate),
        )
        .route(
            "/groups/{group_id}/delete",
            delete(dashboard::alliance::groups::delete),
        )
        .route(
            "/groups/{group_id}/update",
            put(dashboard::alliance::groups::update),
        )
        .route_layer(check_selected_alliance_permission(
            AlliancePermission::GroupsWrite,
        ));

    // Alliance landscape management endpoints
    let landscape_management = Router::new()
        .route("/landscape/add", post(dashboard::alliance::landscape::add))
        .route(
            "/landscape/{entry_id}/delete",
            delete(dashboard::alliance::landscape::delete),
        )
        .route(
            "/landscape/{entry_id}/publish",
            put(dashboard::alliance::landscape::publish),
        )
        .route(
            "/landscape/{entry_id}/unpublish",
            put(dashboard::alliance::landscape::unpublish),
        )
        .route(
            "/landscape/{entry_id}/update",
            put(dashboard::alliance::landscape::update),
        )
        .route_layer(check_selected_alliance_permission(
            AlliancePermission::GroupsWrite,
        ));

    // Alliance settings management endpoints
    let settings_management = Router::new()
        .route(
            "/settings/update",
            put(dashboard::alliance::settings::update),
        )
        .route_layer(check_selected_alliance_permission(
            AlliancePermission::SettingsWrite,
        ));

    // Alliance taxonomy management endpoints
    let taxonomy_management = Router::new()
        .route(
            "/event-categories/add",
            post(dashboard::alliance::event_categories::add),
        )
        .route(
            "/event-categories/{event_category_id}/delete",
            delete(dashboard::alliance::event_categories::delete),
        )
        .route(
            "/event-categories/{event_category_id}/update",
            put(dashboard::alliance::event_categories::update),
        )
        .route(
            "/group-categories/add",
            post(dashboard::alliance::group_categories::add),
        )
        .route(
            "/group-categories/{group_category_id}/delete",
            delete(dashboard::alliance::group_categories::delete),
        )
        .route(
            "/group-categories/{group_category_id}/update",
            put(dashboard::alliance::group_categories::update),
        )
        .route("/regions/add", post(dashboard::alliance::regions::add))
        .route(
            "/regions/{region_id}/delete",
            delete(dashboard::alliance::regions::delete),
        )
        .route(
            "/regions/{region_id}/update",
            put(dashboard::alliance::regions::update),
        )
        .route_layer(check_selected_alliance_permission(
            AlliancePermission::TaxonomyWrite,
        ));

    // Alliance team management endpoints
    let team_management = Router::new()
        .route("/team/add", post(dashboard::alliance::team::add))
        .route(
            "/team/{user_id}/delete",
            delete(dashboard::alliance::team::delete),
        )
        .route(
            "/team/{user_id}/role",
            put(dashboard::alliance::team::update_role),
        )
        .route("/users/search", get(common::search_user))
        .route_layer(check_selected_alliance_permission(
            AlliancePermission::TeamWrite,
        ));

    // Setup router
    Router::new()
        .route(
            "/",
            get(dashboard::alliance::home::page).route_layer(check_alliance_dashboard_permission()),
        )
        .merge(dashboard_read)
        .merge(groups_management)
        .merge(landscape_management)
        .merge(settings_management)
        .merge(taxonomy_management)
        .merge(team_management)
        .route(
            "/{alliance_id}/select",
            put(dashboard::alliance::select_alliance)
                .route_layer(check_path_alliance_permission(AlliancePermission::Read)),
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
            "/events/{event_id}/attendees-with-answers.csv",
            get(dashboard::group::attendees::download_csv_with_answers),
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
        .route(
            "/settings/update",
            get(dashboard::group::settings::update_page),
        )
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
            "/events/{event_id}/attendees/invite",
            post(dashboard::group::attendees::invite_event_attendee),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/attendance",
            delete(dashboard::group::attendees::cancel_event_attendee_attendance),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/check-in",
            post(dashboard::group::attendees::manual_check_in),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/invitation/cancel",
            put(dashboard::group::attendees::cancel_event_attendee_invitation),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/invitation-request/accept",
            put(dashboard::group::attendees::accept_invitation_request),
        )
        .route(
            "/events/{event_id}/attendees/{user_id}/invitation-request/reject",
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
        .route(
            "/events/{event_id}/cancel",
            put(dashboard::group::events::cancel),
        )
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
        .route(
            "/events/{event_id}/update",
            put(dashboard::group::events::update),
        )
        .route(
            "/notifications/{event_id}",
            post(dashboard::group::attendees::send_event_custom_notification),
        )
        .route("/users/search", get(common::search_user))
        .route_layer(check_selected_group_permission(
            GroupPermission::EventsWrite,
        ));

    // Group member management endpoints
    let members_management = Router::new()
        .route(
            "/members/{user_id}/delete",
            delete(dashboard::group::members::delete),
        )
        .route(
            "/members/{user_id}/linkedin-blocklist",
            post(dashboard::group::members::block_linkedin),
        )
        .route(
            "/notifications",
            post(dashboard::group::members::send_group_custom_notification),
        )
        .route_layer(check_selected_group_permission(
            GroupPermission::MembersWrite,
        ));

    // Group settings management endpoints
    let settings_management = Router::new()
        .route("/settings/update", put(dashboard::group::settings::update))
        .route_layer(check_selected_group_permission(
            GroupPermission::SettingsWrite,
        ));

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
        .route_layer(check_selected_group_permission(
            GroupPermission::SponsorsWrite,
        ));

    // Group team management endpoints
    let team_management = Router::new()
        .route("/team/add", post(dashboard::group::team::add))
        .route(
            "/team/{user_id}/delete",
            delete(dashboard::group::team::delete),
        )
        .route(
            "/team/{user_id}/role",
            put(dashboard::group::team::update_role),
        )
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
            "/alliance/{alliance_id}/select",
            put(dashboard::group::select_alliance),
        )
}

/// Sets up the user dashboard router and its routes.
pub(super) fn setup_user_dashboard_router() -> Router<State> {
    // Setup router
    Router::new()
        .route("/", get(dashboard::user::home::page))
        .route("/events", get(dashboard::user::events::list_page))
        .route(
            "/events/{alliance_name}/{event_id}/attendance",
            delete(dashboard::user::events::cancel_attendance),
        )
        .route(
            "/events/{alliance_name}/{event_id}/registration-answers",
            put(dashboard::user::events::submit_registration_answers),
        )
        .route("/invitations", get(dashboard::user::invitations::list_page))
        .route(
            "/invitations/alliance/{alliance_id}/accept",
            put(dashboard::user::invitations::accept_alliance_team_invitation),
        )
        .route(
            "/invitations/alliance/{alliance_id}/reject",
            put(dashboard::user::invitations::reject_alliance_team_invitation),
        )
        .route(
            "/invitations/event/{event_id}/accept",
            put(dashboard::user::invitations::accept_event_attendee_invitation),
        )
        .route(
            "/invitations/event/{event_id}/reject",
            put(dashboard::user::invitations::reject_event_attendee_invitation),
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
            get(dashboard::user::session_proposals::list_page)
                .post(dashboard::user::session_proposals::add),
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
