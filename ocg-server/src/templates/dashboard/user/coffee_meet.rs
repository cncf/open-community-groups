//! Templates for the user dashboard `CoffeeMeet` tab.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// List page showing `CoffeeMeet` subscriptions for the current user.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/user/coffee_meet_list.html")]
pub(crate) struct ListPage {
    /// Groups the user can subscribe to.
    pub subscriptions: Vec<CoffeeMeetSubscription>,
}

/// `CoffeeMeet` subscription row for a user's group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CoffeeMeetSubscription {
    /// Group identifier.
    pub group_id: Uuid,
    /// Group display name.
    pub group_name: String,
    /// Group slug.
    pub group_slug: String,
    /// Alliance slug/name.
    pub alliance_name: String,
    /// Alliance display name.
    pub alliance_display_name: String,
    /// Selected frequency when subscribed.
    pub frequency: Option<String>,
    /// Whether the subscription is currently active.
    pub active: bool,
    /// Next suggestion time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub next_suggestion_at: Option<DateTime<Utc>>,
    /// Last suggestion time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub last_suggestion_at: Option<DateTime<Utc>>,
    /// Last suggested member display name.
    pub last_suggested_name: Option<String>,
    /// Last suggested member username.
    pub last_suggested_username: Option<String>,
}

impl CoffeeMeetSubscription {
    /// Returns the selected frequency or the default.
    pub(crate) fn frequency_or_default(&self) -> &str {
        self.frequency.as_deref().unwrap_or("monthly")
    }

    /// Public group URL.
    pub(crate) fn group_url(&self) -> String {
        format!("/{}/group/{}", self.alliance_name, self.group_slug.as_str())
    }
}

/// `CoffeeMeet` subscription form.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct CoffeeMeetSubscriptionForm {
    /// Group being subscribed to.
    #[garde(skip)]
    pub group_id: Uuid,
    /// Requested cadence.
    #[garde(pattern(r"^(weekly|biweekly|monthly)$"))]
    pub frequency: String,
}

/// `CoffeeMeet` unsubscribe form.
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct CoffeeMeetUnsubscribeForm {
    /// Group being unsubscribed from.
    #[garde(skip)]
    pub group_id: Uuid,
}
