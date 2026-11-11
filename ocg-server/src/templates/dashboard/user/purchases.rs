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
mod tests;
