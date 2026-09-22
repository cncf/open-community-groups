//! Templates for listing event waiting list entries in the group dashboard.

use askama::Template;

use crate::types::dashboard::group::waitlist::{WaitlistEntry, WaitlistSort};
use crate::{
    templates::helpers::user_initials,
    types::{dashboard::group::PresenceFilter, event::EventSummary, pagination},
};

// Pages templates.

/// List waitlist page template for a group's event.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/group/waitlist_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage events.
    pub can_manage_events: bool,
    /// Event for which waitlist entries are listed.
    pub event: EventSummary,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// URL used to refresh the waitlist with the current filters.
    pub refresh_url: String,
    /// Total number of waitlist entries for the selected event.
    pub total: usize,
    /// Waitlist entries for the selected event.
    pub waitlist: Vec<WaitlistEntry>,

    /// Number of results per page.
    pub limit: Option<usize>,
    /// Pagination offset for results.
    pub offset: Option<usize>,
    /// Sort option used to order waitlist entries.
    pub sort: Option<WaitlistSort>,
    /// User title presence filter.
    pub title: Option<PresenceFilter>,
    /// Text search query used to filter waitlist entries.
    pub ts_query: Option<String>,
}

// Helpers.

/// Returns a stable identifier for a waitlist row's actions menu.
///
/// Offer history rows are keyed by their offer, and queued rows by the user
/// and ticket tier, so a user appearing in both keeps distinct menus.
pub(crate) fn waitlist_row_key(entry: &WaitlistEntry) -> String {
    match entry.admission_offer_id {
        Some(admission_offer_id) => format!("waitlist-offer-{admission_offer_id}"),
        None => format!(
            "waitlist-queue-{}-{}",
            entry.user.user_id, entry.event_ticket_type_id
        ),
    }
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use uuid::Uuid;

    use super::waitlist_row_key;
    use crate::types::{dashboard::group::waitlist::WaitlistEntry, user::User};

    fn entry(admission_offer_id: Option<Uuid>) -> WaitlistEntry {
        WaitlistEntry {
            created_at: Utc::now(),
            event_ticket_type_id: Uuid::nil(),
            ticket_title: "General".to_string(),
            user: User {
                user_id: Uuid::max(),
                username: "jane".to_string(),
                ..User::default()
            },
            admission_offer_id,
            admission_offer_status: None,
            offer_expires_at: None,
            waitlist_position: None,
        }
    }

    #[test]
    fn test_waitlist_row_key_uses_offer_for_history_rows() {
        let offer_id = Uuid::from_u128(7);

        assert_eq!(
            waitlist_row_key(&entry(Some(offer_id))),
            format!("waitlist-offer-{offer_id}")
        );
    }

    #[test]
    fn test_waitlist_row_key_uses_user_and_tier_for_queued_rows() {
        assert_eq!(
            waitlist_row_key(&entry(None)),
            format!("waitlist-queue-{}-{}", Uuid::max(), Uuid::nil())
        );
    }
}
