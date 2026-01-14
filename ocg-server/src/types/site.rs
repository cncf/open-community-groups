//! Global site types used across the application.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

// Site types.

/// Statistics for the site home page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[allow(dead_code)]
pub struct SiteHomeStats {
    /// Number of active communities.
    pub communities: i64,
    /// Number of published events.
    pub events: i64,
    /// Number of event attendees.
    pub events_attendees: i64,
    /// Number of active groups.
    pub groups: i64,
    /// Number of group members.
    pub groups_members: i64,
}

/// Global site settings.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SiteSettings {
    /// Brief description of the site.
    pub description: String,
    /// Unique identifier for the site.
    pub site_id: Uuid,
    /// Visual theme configuration.
    pub theme: Theme,
    /// Title shown in the site header and other pages.
    pub title: String,

    /// Copyright text displayed in the footer.
    pub copyright_notice: Option<String>,
    /// URL to the small icon displayed in browser tabs and bookmarks.
    pub favicon_url: Option<String>,
    /// URL to the logo image shown in the page footer.
    pub footer_logo_url: Option<String>,
    /// URL to the logo image shown in the page header.
    pub header_logo_url: Option<String>,
    /// URL to the Open Graph image used for link previews.
    pub og_image_url: Option<String>,
}

// Other related types.

/// Theme information used to customize the site layout.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Theme {
    #[serde(default)]
    pub palette: Palette,
    pub primary_color: String,
}

/// Color palette mapping intensity levels (50-900) to hex color values.
pub type Palette = BTreeMap<u32, String>;
