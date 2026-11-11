//! Templates for listing group refunds in the dashboard.

use askama::Template;
use uuid::Uuid;

use crate::{
    templates::{dashboard::BadgeTone, helpers::user_initials},
    types::{
        dashboard::group::refunds::{
            GroupFinancialRecovery, GroupRefund, GroupRefundStatus, RefundEvent, RefundsView,
        },
        pagination,
    },
};

#[cfg(test)]
mod tests;

// Pages templates.

/// Refunds list page template for a group.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/refunds_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage event refunds.
    pub can_manage_events: bool,
    /// Events available in the event filter.
    pub events: Vec<RefundEvent>,
    /// Exhausted financial work requiring an operator decision.
    pub financial_recoveries: Vec<GroupFinancialRecovery>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Partial URL used to refresh the current refunds view.
    pub refresh_url: String,
    /// List of refunds matching the current filters.
    pub refunds: Vec<GroupRefund>,
    /// Total number of matching refund and financial-recovery operations.
    pub total: usize,
    /// Selected refund view.
    pub view: RefundsView,

    /// Event used to filter refunds.
    pub event_id: Option<Uuid>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Text search query.
    pub ts_query: Option<String>,
}

impl ListPage {
    /// Returns whether an event filter option is selected.
    fn is_event_selected(&self, event_id: &Uuid) -> bool {
        self.event_id.as_ref() == Some(event_id)
    }
}

// Helpers.

/// Returns the badge tone used for a refund status. Askama passes the status
/// by reference.
#[allow(clippy::trivially_copy_pass_by_ref)]
pub(crate) fn status_tone(status: &GroupRefundStatus) -> BadgeTone {
    match status {
        GroupRefundStatus::NeedsReview => BadgeTone::Warning,
        GroupRefundStatus::RecoveryRequired
        | GroupRefundStatus::Rejected
        | GroupRefundStatus::RetryableFailure => BadgeTone::Danger,
        GroupRefundStatus::AwaitingCheckout
        | GroupRefundStatus::Processing
        | GroupRefundStatus::Queued
        | GroupRefundStatus::Refunded => BadgeTone::Neutral,
    }
}
