//! User dashboard notification preference types.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Group whose optional notifications a user muted.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct MutedGroup {
    /// Whether the group is active, not deleted, and in an active community.
    pub available: bool,
    /// Display name of the community the group belongs to.
    pub community_display_name: String,
    /// Group identifier.
    pub group_id: Uuid,
    /// When the user muted the group.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub muted_at: DateTime<Utc>,
    /// Group name.
    pub name: String,

    /// Group logo URL.
    pub logo_url: Option<String>,
}

/// Optional notification categories a user can turn off.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[cfg_attr(test, derive(strum::VariantArray))]
#[serde(rename_all = "kebab-case")]
pub(crate) enum NotificationCategory {
    /// Attendee responses to offers assigned by the organizer.
    AttendeeActivity,
    /// Badge awards and revocations.
    Badges,
    /// Responses to and endings of co-hosting arrangements.
    CohostingUpdates,
    /// Reminders before events the user attends or speaks at.
    EventReminders,
    /// Messages organizers send to group members.
    GroupAnnouncements,
    /// Messages written to groups the user helps manage.
    GroupInbox,
    /// New events and event series published by groups.
    NewEvents,
    /// Messages organizers send to event attendees.
    OrganizerMessages,
    /// Paid ticket setups configured in the user's community.
    PaidEventSetups,
}

/// Connected group a user can mute.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct NotificationGroupOption {
    /// Display name of the community the group belongs to.
    pub community_display_name: String,
    /// Group identifier.
    pub group_id: Uuid,
    /// Group name.
    pub name: String,

    /// Group logo URL.
    pub logo_url: Option<String>,
}

/// Notification preferences of a user.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct NotificationPreferences {
    /// Groups the user muted, including groups no longer available.
    pub muted_groups: Vec<MutedGroup>,
    /// Categories the user turned off.
    pub opted_out_categories: Vec<NotificationCategory>,
}

impl NotificationPreferences {
    /// Returns whether the user receives notifications in the category.
    pub(crate) fn receives(&self, category: NotificationCategory) -> bool {
        !self.opted_out_categories.contains(&category)
    }
}

/// Category preferences submitted from the notifications tab.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Validate)]
pub(crate) struct NotificationPreferencesInput {
    /// Whether each submitted category is enabled; other categories are unchanged.
    #[garde(length(min = 1))]
    pub preferences: BTreeMap<NotificationCategory, bool>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_notification_preferences_receives_excludes_opted_out_categories() {
        let preferences = NotificationPreferences {
            muted_groups: vec![],
            opted_out_categories: vec![NotificationCategory::Badges],
        };

        assert!(!preferences.receives(NotificationCategory::Badges));
        assert!(preferences.receives(NotificationCategory::NewEvents));
    }
}
