//! HTTP handlers for the refunds section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use garde::Validate;
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{
            CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm, ValidatedQuery,
        },
    },
    services::payments::{CompleteRefundRecoveryInput, DynPaymentsManager, PaymentJobRecovery},
    templates::dashboard::group::refunds,
    types::{
        dashboard::group::refunds::RefundsFilters,
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
    validation::{MAX_LEN_DESCRIPTION_SHORT, MAX_LEN_M, trimmed_non_empty},
};

#[cfg(test)]
mod tests;

// URLs used by the dashboard page and tab partial.
const DASHBOARD_URL: &str = "/dashboard/group?tab=refunds";
const PARTIAL_URL: &str = "/dashboard/group/refunds";

// Pages handlers.

/// Displays the purchase refund workflows for a group.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare list page content
    let (filters, template) = prepare_list_page(
        &db,
        community_id,
        group_id,
        user.user_id,
        raw_query.as_deref().unwrap_or_default(),
    )
    .await?;

    // Keep browser navigation on the full dashboard URL
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

// Actions handlers.

/// Completes exhausted payment job work resolved outside OCG.
#[instrument(skip_all, err)]
pub(crate) async fn complete_payment_job_recovery(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(payments_manager): State<DynPaymentsManager>,
    ValidatedForm(input): ValidatedForm<PaymentJobRecoveryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Complete the selected provider operation with the recovery evidence
    payments_manager
        .complete_payment_job_recovery(&PaymentJobRecovery {
            actor_user_id: user.user_id,
            group_id,
            payment_job_id: input.payment_job_id,
            provider_object_id: input.provider_object_id,
            recovery_note: input.recovery_note,
            recovery_reference: input.recovery_reference,
        })
        .await?;

    // Refresh the operator's current refund view
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-refunds")],
    )
        .into_response())
}

/// Completes an externally resolved terminal provider refund.
#[instrument(skip_all, err)]
pub(crate) async fn complete_refund_recovery(
    CurrentUser(user): CurrentUser,
    SelectedGroupId(group_id): SelectedGroupId,
    State(payments_manager): State<DynPaymentsManager>,
    ValidatedForm(input): ValidatedForm<RefundRecoveryInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Compose and persist the recovery through the payments service
    payments_manager
        .complete_refund_recovery(&CompleteRefundRecoveryInput {
            actor_user_id: user.user_id,
            event_purchase_id: input.event_purchase_id,
            group_id,
            recovery_note: input.recovery_note,
            recovery_reference: input.recovery_reference,
        })
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-group-refunds",
        )],
    )
        .into_response())
}

/// Requeues exhausted payment work for another bounded attempt cycle.
#[instrument(skip_all, err)]
pub(crate) async fn retry_payment_job(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(payment_job_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Requeue the selected provider operation
    db.requeue_payment_job(group_id, payment_job_id).await?;

    // Refresh the operator's current refund view
    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-event-attendees, refresh-group-refunds",
        )],
    )
        .into_response())
}

// Helpers.

/// Prepares the refunds list page and filters for the group dashboard.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    community_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(RefundsFilters, refunds::ListPage), HandlerError> {
    // Parse and validate list filters
    let filters: RefundsFilters = ValidatedQuery::parse(raw_query)?;

    // Load refund data and action permissions
    let (can_manage_events, results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user_id,
            GroupPermission::EventsWrite
        ),
        db.list_group_refunds(group_id, &filters)
    )?;

    // Build pagination links
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let refresh_url = pagination::build_url(PARTIAL_URL, &filters)?;
    let template = refunds::ListPage {
        can_manage_events,
        events: results.events,
        financial_recoveries: results.financial_recoveries,
        navigation_links,
        refresh_url,
        refunds: results.refunds,
        total: results.total,
        view: filters.view,
        event_id: filters.event_id,
        offset: filters.offset,
        ts_query: filters.ts_query.clone(),
    };

    Ok((filters, template))
}

// Types.

/// Form data for completing exhausted payment job work outside OCG.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct PaymentJobRecoveryInput {
    /// Durable payment job identifier.
    #[garde(skip)]
    pub payment_job_id: Uuid,
    /// Provider object created outside OCG.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub provider_object_id: String,
    /// Evidence reviewed before completing recovery.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub recovery_note: String,
    /// Reference for the external operation.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub recovery_reference: String,
}

/// Form data for completing an externally resolved refund.
#[derive(Debug, Deserialize, Serialize, Validate)]
pub(crate) struct RefundRecoveryInput {
    /// Purchase whose refund recovery is being completed.
    #[garde(skip)]
    pub event_purchase_id: Uuid,
    /// Evidence reviewed before completing recovery.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION_SHORT))]
    pub recovery_note: String,
    /// Reference for the external refund.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub recovery_reference: String,
}
