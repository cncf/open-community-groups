//! HTTP handlers to manage invitations in the user dashboard.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use axum_messages::Messages;
use tower_sessions::Session;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::{HttpServerConfig, PaymentsConfig},
    db::{DBExt, DynDB, dashboard::user::AcceptEventAdmissionOfferResult},
    handlers::{
        auth::{SELECTED_COMMUNITY_ID_KEY, select_first_community_and_group},
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    services::notifications::enqueue::{
        enqueue_event_welcome_notification,
        enqueue_reconciled_non_ticketed_waitlist_promotion_notification,
    },
    templates::dashboard::user::invitations,
    types::questionnaire::OptionalQuestionnaireAnswersForm,
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Returns the invitations list page for the user dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let template = prepare_list_page(&db, user.user_id).await?;

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Accepts a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_community_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Accept community team invitation
    db.accept_community_team_invitation(user.user_id, community_id)
        .await?;
    messages.success("Team invitation accepted.");

    // Select first community and group if none selected
    if session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?.is_none() {
        select_first_community_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Accepts an exact non-ticketed organizer admission offer.
#[instrument(skip_all, err)]
pub(crate) async fn accept_event_admission_offer(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(server_cfg): State<HttpServerConfig>,
    Path(admission_offer_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<OptionalQuestionnaireAnswersForm>,
) -> Result<impl IntoResponse, HandlerError> {
    let accept_result = db
        .as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Accept the exact offer with any claim-time registration answers
                let accept_result = tx
                    .accept_event_admission_offer(
                        user.user_id,
                        admission_offer_id,
                        input.registration_answers,
                        payments_cfg.as_ref().map(PaymentsConfig::provider),
                    )
                    .await?;

                let AcceptEventAdmissionOfferResult::Accepted(accepted_offer) = accept_result
                else {
                    return Ok(accept_result);
                };

                // Enqueue the welcome notification
                enqueue_event_welcome_notification(
                    tx,
                    &server_cfg,
                    accepted_offer.community_id,
                    accepted_offer.event_id,
                    user.user_id,
                    true,
                )
                .await?;

                Ok(accept_result)
            })
        })
        .await?;

    // Return offer conflicts before reporting successful acceptance
    if let AcceptEventAdmissionOfferResult::Conflict(conflict) = accept_result {
        return Ok((
            StatusCode::CONFLICT,
            axum::Json(serde_json::json!({
                "conflict": conflict,
            })),
        )
            .into_response());
    }

    messages.success("Event invitation accepted.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}

/// Accepts a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn accept_group_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    session: Session,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Mark invitation as accepted
    db.accept_group_team_invitation(user.user_id, group_id).await?;
    messages.success("Team invitation accepted.");

    // Select first community and group if none selected
    if session.get::<Uuid>(SELECTED_COMMUNITY_ID_KEY).await?.is_none() {
        select_first_community_and_group(&db, &session, &user.user_id).await?;
    }

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Declines an active admission offer owned by the current user.
#[instrument(skip_all, err)]
pub(crate) async fn decline_event_admission_offer(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
    State(server_cfg): State<HttpServerConfig>,
    Path(admission_offer_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the configured payment provider before transactional work
    let payment_provider = payments_cfg.as_ref().map(PaymentsConfig::provider);

    // Decline the offer and enqueue non-ticketed waitlist promotions atomically
    db.as_ref()
        .transaction(|tx| {
            Box::pin(async move {
                // Decline the offer and collect any waitlist promotions
                let outcome = tx
                    .decline_event_admission_offer(
                        user.user_id,
                        admission_offer_id,
                        payment_provider,
                    )
                    .await?;

                // Enqueue required non-ticketed waitlist promotions before committing
                enqueue_reconciled_non_ticketed_waitlist_promotion_notification(
                    tx,
                    &server_cfg,
                    outcome.community_id,
                    outcome.group_id,
                    outcome.event_id,
                    outcome.non_ticketed_promoted_user_ids,
                )
                .await
            })
        })
        .await?;
    messages.success("Event offer declined.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending community team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_community_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    Path(community_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject the pending invitation
    db.reject_community_team_invitation(user.user_id, community_id)
        .await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

/// Rejects a pending group team invitation.
#[instrument(skip_all, err)]
pub(crate) async fn reject_group_team_invitation(
    CurrentUser(user): CurrentUser,
    messages: Messages,
    State(db): State<DynDB>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject the pending invitation
    db.reject_group_team_invitation(user.user_id, group_id).await?;
    messages.success("Team invitation rejected.");

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]))
}

// Helpers.

/// Prepares the invitations list page for the user dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
) -> Result<invitations::ListPage, HandlerError> {
    // Prepare template fetching both lists concurrently
    let (community_invitations, event_invitations, group_invitations) = tokio::try_join!(
        db.list_user_community_team_invitations(user_id),
        db.list_user_event_invitations(user_id),
        db.list_user_group_team_invitations(user_id)
    )?;

    Ok(invitations::ListPage {
        community_invitations,
        event_invitations,
        group_invitations,
    })
}
