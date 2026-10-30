//! Templates for attendee purchase document history.

use askama::Template;

use crate::{
    templates::dashboard::BadgeTone,
    types::{
        dashboard::user::purchases::PurchaseDocument, pagination, payments::EventPurchaseStatus,
    },
};

// Pages templates.

/// Purchase-document history page.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/purchases_list.html")]
pub(crate) struct ListPage {
    /// Pagination links for the purchase list.
    pub navigation_links: pagination::NavigationLinks,
    /// Purchases shown on the current page.
    pub purchases: Vec<PurchaseDocument>,
    /// Total number of qualifying purchases.
    pub total: usize,

    /// Pagination offset.
    pub offset: Option<usize>,
}

// Helpers.

/// Returns the badge tone used for a purchase status.
pub(crate) fn status_tone(purchase: &PurchaseDocument) -> BadgeTone {
    match purchase.status {
        EventPurchaseStatus::Completed => BadgeTone::Success,
        EventPurchaseStatus::RefundRecoveryPending | EventPurchaseStatus::RefundRequested => {
            BadgeTone::Warning
        }
        EventPurchaseStatus::Expired
        | EventPurchaseStatus::Pending
        | EventPurchaseStatus::Refunded
        | EventPurchaseStatus::RefundPending => BadgeTone::Neutral,
    }
}

#[cfg(test)]
mod tests {
    use askama::Template;
    use chrono::{TimeZone, Utc};
    use uuid::Uuid;

    use crate::{
        templates::dashboard::BadgeTone,
        types::{
            dashboard::user::purchases::{CreditNoteDocument, PurchaseDocument},
            pagination::NavigationLinks,
            payments::EventPurchaseStatus,
        },
    };

    use super::{ListPage, status_tone};

    #[test]
    fn test_list_page_renders_document_routes_for_past_refunded_purchase() {
        let event_purchase_credit_note_id = Uuid::new_v4();
        let event_purchase_id = Uuid::new_v4();
        let mut purchase = sample_purchase(event_purchase_id);
        purchase.status = EventPurchaseStatus::Refunded;
        purchase.provider_invoice_id = Some("in_purchase".to_string());
        purchase.credit_notes = vec![CreditNoteDocument {
            event_purchase_credit_note_id,
            provider_credit_note_id: Some("cn_purchase".to_string()),
            status: "completed".to_string(),
        }];
        let html = render_purchase(purchase);

        assert!(html.contains(&format!(
            "/dashboard/user/purchases/{event_purchase_id}/invoice"
        )));
        assert!(html.contains(&format!(
            "/dashboard/user/purchases/{event_purchase_id}/credit-notes/{event_purchase_credit_note_id}"
        )));
        assert!(html.contains("Refunded"));
        assert!(html.contains("custom-badge badge-neutral"));
        assert!(!html.contains("badge-pending"));
        assert!(html.contains("Event Jul 01, 2026"));
        assert!(html.contains("target=\"_blank\""));
        assert!(html.contains("rel=\"noopener noreferrer\""));
    }

    #[test]
    fn test_list_page_renders_processing_states_when_documents_are_missing() {
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

    #[test]
    fn test_status_tone() {
        let cases = [
            (
                "completed",
                EventPurchaseStatus::Completed,
                BadgeTone::Success,
            ),
            ("expired", EventPurchaseStatus::Expired, BadgeTone::Neutral),
            ("pending", EventPurchaseStatus::Pending, BadgeTone::Neutral),
            (
                "refunded",
                EventPurchaseStatus::Refunded,
                BadgeTone::Neutral,
            ),
            (
                "refund pending",
                EventPurchaseStatus::RefundPending,
                BadgeTone::Neutral,
            ),
            (
                "refund recovery pending",
                EventPurchaseStatus::RefundRecoveryPending,
                BadgeTone::Warning,
            ),
            (
                "refund requested",
                EventPurchaseStatus::RefundRequested,
                BadgeTone::Warning,
            ),
        ];

        for (case, status, expected) in cases {
            let mut purchase = sample_purchase(Uuid::new_v4());
            purchase.status = status;

            assert_eq!(status_tone(&purchase), expected, "{case}");
        }
    }

    fn render_purchase(purchase: PurchaseDocument) -> String {
        ListPage {
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
            externally_managed: false,
            group_slug_pretty: None,
            provider_invoice_id: None,
            seller_display_name: Some("Fiscal Sponsor".to_string()),
        }
    }
}
