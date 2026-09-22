//! HTTP handlers for group settings management.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    config::PaymentsConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    services::payments::{AutomaticTaxReadinessError, DynPaymentsManager},
    templates::dashboard::group::settings,
    types::{
        dashboard::community::groups::GroupInput, payments::PaymentConfigurationValidation,
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the page to update group settings.
#[instrument(skip_all)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let template = prepare_update_page(
        &db,
        community_id,
        group_id,
        user.user_id,
        payments_cfg.is_some(),
    )
    .await?;

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates group settings in the database.
#[instrument(skip_all)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_manager): State<DynPaymentsManager>,
    ValidatedFormQs(mut group_update): ValidatedFormQs<GroupInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Normalize provider account fields before comparison, validation, and persistence
    if let Some(recipient) = group_update.payment_recipient.as_mut() {
        recipient.recipient_id = recipient.recipient_id.trim().to_string();
        recipient.seller_display_name = recipient.seller_display_name.trim().to_string();
    }

    // Normalize the external payee legal name, keeping a blank value so the
    // database clears the stored name
    if let Some(seller_display_name) = group_update.external_payments_seller_display_name.as_mut() {
        *seller_display_name = seller_display_name.trim().to_string();
    }

    // Validate a changed provider account before persisting it
    let mut payment_validation = None;
    if let Some(recipient) = group_update
        .payment_recipient
        .as_ref()
        .filter(|recipient| !recipient.recipient_id.trim().is_empty())
    {
        let current_recipient = db.get_group_payment_recipient(community_id, group_id).await?;
        let provider_account_changed = current_recipient.as_ref().is_none_or(|current| {
            current.provider != recipient.provider || current.recipient_id != recipient.recipient_id
        });
        if provider_account_changed {
            // Avoid provider calls for a request already known to be blocked; the
            // database re-evaluates the policy visible when its own guard runs
            if db
                .get_group_external_payments_eligibility(
                    community_id,
                    group_id,
                    group_update.country_code.clone(),
                )
                .await?
            {
                return Err(HandlerError::Rejected(
                    "stripe connected account cannot be added or changed for this group country"
                        .to_string(),
                ));
            }

            let require_automatic_tax = db
                .group_requires_automatic_tax_readiness(community_id, group_id)
                .await?;
            payments_manager.validate_fiscal_sponsor(recipient, None).await?;

            // Recheck each upcoming automatic-tax event against the new sponsor
            if require_automatic_tax {
                let event_ids = db
                    .list_group_automatic_tax_readiness_event_ids(community_id, group_id)
                    .await?;
                for event_id in event_ids {
                    let event = db.get_event_full(community_id, group_id, event_id).await?;
                    payments_manager
                        .ensure_automatic_tax_readiness(recipient, &event.ticket_venue())
                        .await
                        .map_err(|error| upcoming_event_automatic_tax_error(&event.name, error))?;
                }
            }
            payment_validation = Some(PaymentConfigurationValidation {
                require_automatic_tax,

                expected_payment_recipient: current_recipient,
                manual_tax_rate_ids: None,
                tax_behavior: None,
                tax_calculation_mode: None,
                validated_payment_recipient: Some(recipient.clone()),
            });
        }
    }
    group_update.payment_validation = payment_validation;

    // Update group in database
    db.update_group(user.user_id, community_id, group_id, &group_update)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}

// Helpers.

/// Prepares the group settings update page template.
pub(crate) async fn prepare_update_page(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    payments_enabled: bool,
) -> Result<settings::UpdatePage> {
    // Load the settings page context concurrently
    let (
        can_manage_settings,
        group,
        has_child_links,
        categories,
        parent_options,
        regions,
        external_payments,
    ) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user_id,
            GroupPermission::SettingsWrite
        ),
        db.get_group_full(community_id, group_id),
        db.group_has_child_links(community_id, group_id),
        db.list_group_categories(community_id),
        db.list_group_parent_options(community_id, user_id, Some(group_id)),
        db.list_regions(community_id),
        db.get_group_external_payments_context(community_id, group_id)
    )?;

    Ok(settings::UpdatePage {
        can_manage_settings,
        categories,
        external_payments,
        group,
        has_child_links,
        parent_options,
        payments_enabled,
        regions,
    })
}

/// Maps an upcoming-event readiness failure onto the fiscal-sponsor update.
fn upcoming_event_automatic_tax_error(
    event_name: &str,
    error: AutomaticTaxReadinessError,
) -> HandlerError {
    match HandlerError::from(error) {
        HandlerError::Rejected(message) => HandlerError::Rejected(format!(
            "cannot update fiscal sponsor: upcoming event \"{event_name}\" is not ready for payments: {message}"
        )),
        other => other,
    }
}
