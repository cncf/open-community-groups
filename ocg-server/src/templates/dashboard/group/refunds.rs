//! Templates and types for listing group refunds in the dashboard.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::{NoneAsEmptyString, serde_as, skip_serializing_none};
use uuid::Uuid;

use crate::{
    templates::{dashboard, helpers::user_initials},
    types::{
        pagination::{self, Pagination, ToRawQuery},
        payments::format_amount_minor,
    },
    validation::{MAX_LEN_M, MAX_PAGINATION_LIMIT, trimmed_non_empty_opt},
};

// Pages templates.

/// Refunds list page template for a group.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/refunds_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage event refunds.
    pub can_manage_events: bool,
    /// Events available in the event filter.
    pub events: Vec<RefundEvent>,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Partial URL used to refresh the current refunds view.
    pub refresh_url: String,
    /// List of refunds matching the current filters.
    pub refunds: Vec<GroupRefund>,
    /// Total number of matching refunds.
    pub total: usize,
    /// Selected refund view.
    pub view: RefundsView,
    /// Refund view links.
    pub views: Vec<RefundsViewOption>,

    /// Event used to filter refunds.
    pub event_id: Option<Uuid>,
    /// Number of results per page.
    pub limit: Option<usize>,
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

// Types.

/// Refund row shown in the group dashboard.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupRefund {
    /// Purchase amount in minor units.
    pub amount_minor: i64,
    /// Time when the refund workflow was created.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Purchase currency code.
    pub currency_code: String,
    /// Attendee email address.
    pub email: String,
    /// Event identifier.
    pub event_id: Uuid,
    /// Event name.
    pub event_name: String,
    /// Purchase identifier.
    pub event_purchase_id: Uuid,
    /// Consolidated refund status.
    pub status: GroupRefundStatus,
    /// Ticket title snapshot.
    pub ticket_title: String,
    /// Most recent refund workflow update.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub updated_at: DateTime<Utc>,
    /// Attendee identifier.
    pub user_id: Uuid,
    /// Attendee username.
    pub username: String,

    /// Number of provider attempts made.
    pub attempt_count: Option<i32>,
    /// Last provider failure message.
    pub failure_message: Option<String>,
    /// Refund workflow kind.
    pub kind: Option<String>,
    /// Attendee name.
    pub name: Option<String>,
    /// Attendee profile photo URL.
    pub photo_url: Option<String>,
    /// Provider refund identifier.
    pub provider_refund_id: Option<String>,
    /// Reason supplied with an attendee refund request.
    pub requested_reason: Option<String>,
    /// Organizer review note.
    pub review_note: Option<String>,
}

impl GroupRefund {
    /// Returns whether this refund request can be approved.
    pub(crate) fn can_approve(&self) -> bool {
        self.status == GroupRefundStatus::NeedsReview
    }

    /// Returns whether this refund request can be rejected.
    pub(crate) fn can_reject(&self) -> bool {
        self.status == GroupRefundStatus::NeedsReview
    }

    /// Returns whether this refund requires external recovery.
    pub(crate) fn can_recover(&self) -> bool {
        self.status == GroupRefundStatus::RecoveryRequired
    }

    /// Returns whether this refund can be manually retried.
    pub(crate) fn can_retry(&self) -> bool {
        self.status == GroupRefundStatus::RetryableFailure
    }

    /// Formats the purchase amount for display.
    pub(crate) fn formatted_amount(&self) -> String {
        if self.amount_minor == 0 {
            return "Free".to_string();
        }

        format_amount_minor(self.amount_minor, &self.currency_code)
    }

    /// Returns the user-facing refund workflow label.
    pub(crate) fn kind_label(&self) -> &'static str {
        match self.kind.as_deref() {
            Some("automatic-unfulfillable-checkout") => "Checkout refund",
            Some("event-cancellation") => "Event cancellation",
            Some("refund-request-approval") => "Attendee request",
            _ => "Refund",
        }
    }
}

/// Consolidated operational status for a group refund.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum GroupRefundStatus {
    /// Checkout has not completed, so provider work cannot start yet.
    AwaitingCheckout,
    /// The refund request awaits organizer review.
    NeedsReview,
    /// Provider or local refund work is in progress.
    Processing,
    /// Durable refund work is waiting for a worker or retry delay.
    Queued,
    /// A provider outcome requires external recovery.
    RecoveryRequired,
    /// The purchase refund completed.
    Refunded,
    /// The attendee refund request was rejected.
    Rejected,
    /// Automatic attempts were exhausted and can be manually retried.
    RetryableFailure,
}

impl GroupRefundStatus {
    /// Returns the user-facing status label.
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::AwaitingCheckout => "Waiting for checkout",
            Self::NeedsReview => "Needs review",
            Self::Processing => "Processing",
            Self::Queued => "Queued",
            Self::RecoveryRequired => "Recovery required",
            Self::Refunded => "Refunded",
            Self::Rejected => "Rejected",
            Self::RetryableFailure => "Needs retry",
        }
    }

    /// Returns the badge tone used for this status.
    pub(crate) fn tone(self) -> &'static str {
        match self {
            Self::RecoveryRequired | Self::Rejected | Self::RetryableFailure => "danger",
            Self::Refunded => "success",
            _ => "pending",
        }
    }
}

/// Event option available in the refunds filter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct RefundEvent {
    /// Event identifier.
    pub event_id: Uuid,
    /// Event name.
    pub name: String,
}

/// Filter parameters for the group refunds list.
#[serde_as]
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct RefundsFilters {
    /// Event used to filter refunds.
    #[serde_as(as = "NoneAsEmptyString")]
    #[serde(default)]
    #[garde(skip)]
    pub event_id: Option<Uuid>,
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset for results.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
    /// Text search query.
    #[serde(default, deserialize_with = "crate::validation::blank_string_as_none")]
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_M))]
    pub ts_query: Option<String>,
    /// Selected refund view.
    #[serde(default)]
    #[garde(skip)]
    pub view: RefundsView,
}

crate::impl_pagination_and_raw_query!(RefundsFilters, limit, offset);

/// Paginated group refunds response data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct RefundsOutput {
    /// Events available in the event filter.
    pub events: Vec<RefundEvent>,
    /// Refunds matching the current filters.
    pub refunds: Vec<GroupRefund>,
    /// Total number of matching refunds.
    pub total: usize,
}

/// Supported operational views for group refunds.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, strum::Display)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub(crate) enum RefundsView {
    /// Show all unfinished refund work.
    #[default]
    Active,
    /// Show every refund workflow.
    All,
    /// Show refund work requiring an organizer decision or intervention.
    Attention,
    /// Show completed and rejected refund workflows.
    Completed,
}

/// Link for a group refunds operational view.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct RefundsViewOption {
    /// Dashboard URL used for normal navigation.
    pub dashboard_url: String,
    /// Whether this view is currently selected.
    pub is_selected: bool,
    /// User-facing view label.
    pub label: String,
    /// Partial URL used by HTMX navigation.
    pub partial_url: String,
}
