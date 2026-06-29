//! Templates for the group dashboard `CoffeeMeet` tab.

use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::templates::helpers::user_initials;

/// Group dashboard `CoffeeMeet` subscriber list.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/coffee_meet_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage members.
    pub can_manage_members: bool,
    /// Active `CoffeeMeet` subscribers.
    pub subscribers: Vec<CoffeeMeetSubscriber>,
}

/// Active `CoffeeMeet` subscriber row.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CoffeeMeetSubscriber {
    /// User identifier.
    pub user_id: Uuid,
    /// Username.
    pub username: String,
    /// Full name.
    pub name: Option<String>,
    /// Avatar URL.
    pub photo_url: Option<String>,
    /// Selected frequency.
    pub frequency: String,
    /// Next suggestion time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub next_suggestion_at: DateTime<Utc>,
    /// Last suggestion time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub last_suggestion_at: Option<DateTime<Utc>>,
    /// Total suggestions generated for this member.
    pub suggestions_total: i64,
}

impl CoffeeMeetSubscriber {
    /// Display name fallback.
    pub(crate) fn display_name(&self) -> &str {
        self.name.as_deref().unwrap_or(&self.username)
    }

    /// Human-readable frequency.
    pub(crate) fn frequency_label(&self) -> &'static str {
        match self.frequency.as_str() {
            "weekly" => "Weekly",
            "biweekly" => "Bi-weekly",
            _ => "Monthly",
        }
    }
}
