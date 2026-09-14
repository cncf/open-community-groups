//! User dashboard purchase types.

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    types::{
        dashboard,
        pagination::{Pagination, ToRawQuery},
        payments::{EventPurchaseStatus, format_amount_minor},
    },
    validation::MAX_PAGINATION_LIMIT,
};

/// One issued or pending credit-note document.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CreditNoteDocument {
    /// Durable OCG credit-note identifier.
    pub event_purchase_credit_note_id: Uuid,
    /// Durable credit-note lifecycle status.
    pub status: String,

    /// Provider credit-note identifier.
    pub provider_credit_note_id: Option<String>,
}

impl CreditNoteDocument {
    /// Returns the attendee-facing lifecycle label.
    pub(crate) fn status_label(&self) -> &'static str {
        match self.status.as_str() {
            "completed" => "Issued",
            "failed" => "Needs review",
            _ => "Processing",
        }
    }
}

/// Durable attendee purchase and its provider financial documents.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PurchaseDocument {
    /// Total amount collected from the attendee.
    pub amount_minor: i64,
    /// Community URL name.
    pub community_name: String,
    /// Purchase creation timestamp.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Purchase currency.
    pub currency_code: String,
    /// Whether the event was canceled.
    pub event_canceled: bool,
    /// Event display name.
    pub event_name: String,
    /// Purchase identifier.
    pub event_purchase_id: Uuid,
    /// Event URL slug.
    pub event_slug: String,
    /// Event timezone.
    pub event_timezone: chrono_tz::Tz,
    /// Group display name.
    pub group_name: String,
    /// Generated group slug.
    pub group_slug: String,
    /// Purchase lifecycle status.
    pub status: EventPurchaseStatus,
    /// Ticket title snapshot.
    pub ticket_title: String,

    /// Purchase completion timestamp.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub completed_at: Option<DateTime<Utc>>,
    /// Credit notes linked to full purchase refunds.
    #[serde(default)]
    pub credit_notes: Vec<CreditNoteDocument>,
    /// Event start timestamp, including past events.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub event_starts_at: Option<DateTime<Utc>>,
    /// Whether this purchase was collected and documented outside OCG.
    #[serde(default)]
    pub externally_managed: bool,
    /// Admin-managed group slug.
    pub group_slug_pretty: Option<String>,
    /// Durable provider invoice identifier.
    pub provider_invoice_id: Option<String>,
    /// Fiscal sponsor display-name snapshot.
    pub seller_display_name: Option<String>,
}

impl PurchaseDocument {
    /// Returns the amount paid in display form.
    pub(crate) fn formatted_amount(&self) -> String {
        format_amount_minor(self.amount_minor, &self.currency_code)
    }

    /// Returns the group slug used in public links.
    pub(crate) fn public_group_slug(&self) -> &str {
        self.group_slug_pretty.as_deref().unwrap_or(&self.group_slug)
    }

    /// Returns the attendee-facing purchase status.
    pub(crate) fn status_label(&self) -> &'static str {
        match self.status {
            EventPurchaseStatus::Completed => "Paid",
            EventPurchaseStatus::Refunded => "Refunded",
            EventPurchaseStatus::RefundPending => "Refund processing",
            EventPurchaseStatus::RefundRecoveryPending => "Refund needs review",
            EventPurchaseStatus::RefundRequested => "Refund requested",
            EventPurchaseStatus::Expired | EventPurchaseStatus::Pending => "Pending",
        }
    }
}

/// Pagination filters for purchase document history.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct PurchaseDocumentsFilters {
    /// Number of results per page.
    #[serde(default = "dashboard::default_limit")]
    #[garde(range(min = 1, max = MAX_PAGINATION_LIMIT))]
    pub limit: Option<usize>,
    /// Pagination offset.
    #[serde(default = "dashboard::default_offset")]
    #[garde(skip)]
    pub offset: Option<usize>,
}

crate::impl_pagination_and_raw_query!(PurchaseDocumentsFilters, limit, offset);

/// Paginated purchase-document output.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PurchaseDocumentsOutput {
    /// Purchases on the selected page.
    pub purchases: Vec<PurchaseDocument>,
    /// Total qualifying purchase count.
    pub total: usize,
}
