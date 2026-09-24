//! HTTP handlers for the group dashboard.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::PaymentsConfig,
    db::DynDB,
    handlers::{
        auth::session_context::{
            SELECTED_GROUP_ID_KEY, SelectedGroupPolicy, sync_selected_community_and_group,
        },
        error::HandlerError,
        extractors::CurrentUser,
    },
    types::payments::GroupPaymentRecipient,
};

#[cfg(test)]
mod tests;

pub(crate) mod analytics;
pub(crate) mod attendees;
pub(crate) mod badges;
pub(crate) mod check_in;
pub(crate) mod cohosts;
pub(crate) mod events;
pub(crate) mod home;
pub(crate) mod invitation_requests;
pub(crate) mod logs;
pub(crate) mod members;
pub(crate) mod refunds;
pub(crate) mod settings;
pub(crate) mod sponsors;
pub(crate) mod submissions;
pub(crate) mod team;
pub(crate) mod waitlist;

/// HTMX events that refresh the event enrollment tabs and the refunds list.
///
/// Extends [`EVENT_ENROLLMENT_REFRESH_TRIGGER`] for actions that also change
/// refund state.
pub(crate) const EVENT_ENROLLMENT_AND_REFUNDS_REFRESH_TRIGGER: &str = "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist, refresh-group-refunds";

/// HTMX events that refresh every event tab whose rows depend on enrollment.
///
/// Attendees, Requests, and Waitlist rows all derive from the same enrollment
/// state, so any action that changes it refreshes all three loaded tabs.
pub(crate) const EVENT_ENROLLMENT_REFRESH_TRIGGER: &str =
    "refresh-event-attendees, refresh-event-invitation-requests, refresh-event-waitlist";

/// Checks whether group payments match the configured server provider.
pub(crate) fn payments_ready(
    payment_recipient: Option<&GroupPaymentRecipient>,
    payments_cfg: Option<&PaymentsConfig>,
) -> bool {
    matches!(
        (payment_recipient, payments_cfg),
        (Some(payment_recipient), Some(payments_cfg))
            if payment_recipient.provider == payments_cfg.provider()
    )
}

/// Sets the selected community and auto-selects the first group in session.
#[instrument(skip_all)]
pub(crate) async fn select_community(
    CurrentUser(user): CurrentUser,
    session: Session,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update the selected community and group in the session
    sync_selected_community_and_group(
        &db,
        &session,
        &user.user_id,
        community_id,
        SelectedGroupPolicy::Required,
    )
    .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Sets the selected group in the session for the current user.
#[instrument(skip_all)]
pub(crate) async fn select_group(
    session: Session,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update the selected group in the session
    session.insert(SELECTED_GROUP_ID_KEY, group_id).await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}
