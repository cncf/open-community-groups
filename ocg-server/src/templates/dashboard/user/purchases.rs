//! Templates and types for attendee purchase document history.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::dashboard,
    types::{
        pagination::{self, Pagination, ToRawQuery},
        payments::{EventPurchaseStatus, format_amount_minor},
    },
    validation::MAX_PAGINATION_LIMIT,
};

// Pages templates.

/// Purchase-document history page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/purchases_list.html")]
pub(crate) struct ListPage {
    /// Pagination links for the purchase list.
    pub navigation_links: pagination::NavigationLinks,
    /// Purchases shown on the current page.
    pub purchases: Vec<PurchaseDocument>,
    /// Total number of qualifying purchases.
    pub total: usize,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset.
    pub offset: Option<usize>,
}

// Types.

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
            "issued" => "Issued",
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

#[cfg(test)]
mod tests {
    use askama::Template;
    use chrono::{TimeZone, Utc};
    use uuid::Uuid;

    use crate::types::{pagination::NavigationLinks, payments::EventPurchaseStatus};

    use super::{CreditNoteDocument, ListPage, PurchaseDocument};

    #[test]
    fn list_page_renders_document_routes_for_past_refunded_purchase() {
        let event_purchase_credit_note_id = Uuid::new_v4();
        let event_purchase_id = Uuid::new_v4();
        let mut purchase = sample_purchase(event_purchase_id);
        purchase.status = EventPurchaseStatus::Refunded;
        purchase.provider_invoice_id = Some("in_purchase".to_string());
        purchase.credit_notes = vec![CreditNoteDocument {
            event_purchase_credit_note_id,
            provider_credit_note_id: Some("cn_purchase".to_string()),
            status: "issued".to_string(),
        }];
        let html = render_purchase(purchase);

        assert!(html.contains(&format!(
            "/dashboard/user/purchases/{event_purchase_id}/invoice"
        )));
        assert!(html.contains(&format!(
            "/dashboard/user/purchases/{event_purchase_id}/credit-notes/{event_purchase_credit_note_id}"
        )));
        assert!(html.contains("Refunded"));
        assert!(html.contains("Event Jul 01, 2026"));
        assert!(html.contains("target=\"_blank\""));
        assert!(html.contains("rel=\"noopener noreferrer\""));
    }

    #[test]
    fn list_page_renders_processing_states_when_documents_are_missing() {
        let mut purchase = sample_purchase(Uuid::new_v4());
        purchase.credit_notes = vec![CreditNoteDocument {
            event_purchase_credit_note_id: Uuid::new_v4(),
            provider_credit_note_id: None,
            status: "pending".to_string(),
        }];
        let html = render_purchase(purchase);

        assert!(html.contains("Invoice processing"));
        assert!(html.contains("Credit note processing"));
    }

    fn render_purchase(purchase: PurchaseDocument) -> String {
        ListPage {
            limit: Some(20),
            navigation_links: NavigationLinks::default(),
            offset: Some(0),
            purchases: vec![purchase],
            total: 1,
        }
        .render()
        .unwrap()
    }

    fn sample_purchase(event_purchase_id: Uuid) -> PurchaseDocument {
        PurchaseDocument {
            amount_minor: 2_500,
            community_name: "community".to_string(),
            created_at: Utc.with_ymd_and_hms(2026, 6, 1, 10, 0, 0).single().unwrap(),
            currency_code: "USD".to_string(),
            event_canceled: true,
            event_name: "Past Event".to_string(),
            event_purchase_id,
            event_slug: "past-event".to_string(),
            event_timezone: chrono_tz::UTC,
            group_name: "Group".to_string(),
            group_slug: "group".to_string(),
            status: EventPurchaseStatus::Completed,
            ticket_title: "General admission".to_string(),

            completed_at: Some(Utc.with_ymd_and_hms(2026, 6, 1, 10, 0, 0).single().unwrap()),
            credit_notes: Vec::new(),
            event_starts_at: Some(Utc.with_ymd_and_hms(2026, 7, 1, 10, 0, 0).single().unwrap()),
            group_slug_pretty: None,
            provider_invoice_id: None,
            seller_display_name: Some("Fiscal Sponsor".to_string()),
        }
    }
}
