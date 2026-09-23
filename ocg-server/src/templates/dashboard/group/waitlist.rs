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

/// Returns a stable identifier for a waitlist row's actions menu, keyed by the person the row represents.
pub(crate) fn waitlist_row_key(entry: &WaitlistEntry) -> String {
    format!("waitlist-{}", entry.user.user_id)
}

#[cfg(test)]
mod tests {
    use chrono::Utc;
    use uuid::Uuid;

    use super::waitlist_row_key;
    use crate::types::{
        dashboard::group::waitlist::WaitlistEntry, event::EventAdmissionOfferStatus, user::User,
    };

    fn entry(
        user_id: Uuid,
        admission_offer_id: Option<Uuid>,
        status: Option<EventAdmissionOfferStatus>,
    ) -> WaitlistEntry {
        WaitlistEntry {
            created_at: Utc::now(),
            event_ticket_type_id: Uuid::nil(),
            ticket_title: "General".to_string(),
            user: User {
                user_id,
                username: "jane".to_string(),
                ..User::default()
            },
            admission_offer_id,
            admission_offer_status: status,
            offer_expires_at: None,
            waitlist_position: None,
        }
    }

    #[test]
    fn test_waitlist_row_key_differs_between_users() {
        assert_ne!(
            waitlist_row_key(&entry(Uuid::from_u128(1), None, None)),
            waitlist_row_key(&entry(Uuid::from_u128(2), None, None))
        );
    }

    #[test]
    fn test_waitlist_row_key_is_stable_for_the_same_user() {
        let user_id = Uuid::max();
        let queued = entry(user_id, None, None);
        let pending_offer = entry(
            user_id,
            Some(Uuid::from_u128(7)),
            Some(EventAdmissionOfferStatus::Pending),
        );
        let expired_offer = entry(
            user_id,
            Some(Uuid::from_u128(8)),
            Some(EventAdmissionOfferStatus::Expired),
        );

        assert_eq!(waitlist_row_key(&queued), format!("waitlist-{user_id}"));
        assert_eq!(waitlist_row_key(&pending_offer), waitlist_row_key(&queued));
        assert_eq!(waitlist_row_key(&expired_offer), waitlist_row_key(&queued));
    }
}
