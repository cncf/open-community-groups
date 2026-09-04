//! HTTP handlers for group settings management.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    config::PaymentsConfig,
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedFormQs},
    },
    services::payments::{AutomaticTaxReadinessError, DynPaymentsManager},
    templates::dashboard::group::settings::{self, GroupUpdate},
    types::{payments::PaymentConfigurationValidation, permissions::GroupPermission},
};

use super::events::{automatic_tax_handler_error, event_venue};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the page to update group settings.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_cfg): State<Option<PaymentsConfig>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_settings, group, has_child_links, categories, parent_options, regions) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::SettingsWrite
        ),
        db.get_group_full(community_id, group_id),
        db.group_has_child_links(community_id, group_id),
        db.list_group_categories(community_id),
        db.list_group_parent_options(community_id, user.user_id, Some(group_id)),
        db.list_regions(community_id)
    )?;
    let external_payments = db.get_group_external_payments_context(community_id, group_id).await?;
    let template = settings::UpdatePage {
        can_manage_settings,
        categories,
        external_payments,
        group,
        has_child_links,
        parent_options,
        payments_enabled: payments_cfg.is_some(),
        regions,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Updates group settings in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(payments_manager): State<DynPaymentsManager>,
    ValidatedFormQs(mut group_update): ValidatedFormQs<GroupUpdate>,
) -> Result<impl IntoResponse, HandlerError> {
    // Normalize provider account fields before comparison, validation, and persistence
    if let Some(recipient) = group_update.payment_recipient.as_mut() {
        recipient.recipient_id = recipient.recipient_id.trim().to_string();
        recipient.seller_display_name = recipient.seller_display_name.trim().to_string();
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
                        .ensure_automatic_tax_readiness(recipient, &event_venue(&event))
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

/// Maps an upcoming-event readiness failure onto the fiscal-sponsor update.
fn upcoming_event_automatic_tax_error(
    event_name: &str,
    error: AutomaticTaxReadinessError,
) -> HandlerError {
    match automatic_tax_handler_error(error) {
        HandlerError::Database(message) => HandlerError::Database(format!(
            "cannot update fiscal sponsor: upcoming event \"{event_name}\" is not ready for payments: {message}"
        )),
        other => other,
    }
}
