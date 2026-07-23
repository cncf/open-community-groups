//! HTTP handlers for the refunds section in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{RawQuery, State},
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
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    services::payments::{CompleteRefundRecoveryInput, DynPaymentsManager},
    templates::dashboard::group::refunds::{self, RefundsFilters, RefundsView, RefundsViewOption},
    types::{
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
    let filters: RefundsFilters = serde_qs_config().deserialize_str(raw_query)?;
    filters.validate()?;

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

    // Build pagination and operational view links
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;
    let refresh_url = pagination::build_url(PARTIAL_URL, &filters)?;
    let views = [
        (RefundsView::Active, "Active"),
        (RefundsView::Attention, "Needs attention"),
        (RefundsView::Completed, "Completed"),
        (RefundsView::All, "All"),
    ]
    .into_iter()
    .map(|(view, label)| build_view_option(&filters, view, label))
    .collect::<Result<Vec<_>>>()?;
    let template = refunds::ListPage {
        can_manage_events,
        events: results.events,
        navigation_links,
        refresh_url,
        refunds: results.refunds,
        total: results.total,
        view: filters.view,
        views,
        event_id: filters.event_id,
        limit: filters.limit,
        offset: filters.offset,
        ts_query: filters.ts_query.clone(),
    };

    Ok((filters, template))
}

// Types.

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

/// Builds a dashboard and partial link for one operational refund view.
fn build_view_option(
    filters: &RefundsFilters,
    view: RefundsView,
    label: &str,
) -> Result<RefundsViewOption> {
    // Reset pagination when moving between operational views
    let mut view_filters = filters.clone();
    view_filters.offset = Some(0);
    view_filters.view = view;

    Ok(RefundsViewOption {
        dashboard_url: pagination::build_url(DASHBOARD_URL, &view_filters)?,
        is_selected: filters.view == view,
        label: label.to_string(),
        partial_url: pagination::build_url(PARTIAL_URL, &view_filters)?,
    })
}
