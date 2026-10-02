//! Templates for the user dashboard notifications tab.

use askama::Template;

use crate::types::dashboard::user::notifications::{
    MutedGroup, NotificationCategory, NotificationPreferences,
};

// Pages templates.

/// Notification preferences and muted groups pane.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/notifications.html")]
pub(crate) struct Page {
    /// Current notification preferences of the user.
    pub preferences: NotificationPreferences,
    /// Whether the community organizing section is shown.
    pub show_community_team_section: bool,
    /// Whether the group organizing section is shown.
    pub show_group_team_section: bool,
}

/// Inner content of the muted groups list.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/notifications_muted_groups.html")]
pub(crate) struct MutedGroupsList {
    /// Groups the user muted, including groups no longer available.
    pub muted_groups: Vec<MutedGroup>,
}
