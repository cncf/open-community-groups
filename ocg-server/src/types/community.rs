//! Community-related types used across the application.

use std::collections::BTreeMap;

use anyhow::Result;
use palette::{Darken, Lighten, Srgb};
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

// Community types.

/// Community information used in some community pages.
#[allow(clippy::struct_field_names)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Community {
    /// Whether the community is active.
    pub active: bool,
    /// Unique identifier for the community.
    pub community_id: Uuid,
    /// Layout identifier for the community site.
    pub community_site_layout_id: String,
    /// Creation timestamp in milliseconds since epoch.
    pub created_at: i64,
    /// Brief description of the community's purpose or focus.
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "CNCF").
    pub display_name: String,
    /// URL to the logo image shown in the page header.
    pub header_logo_url: String,
    /// Host domain for the community.
    pub host: String,
    /// Unique identifier used in URLs and database references.
    pub name: String,
    /// Visual theme configuration including primary color and palette.
    pub theme: Theme,
    /// Title highlighted in the community site and other pages.
    pub title: String,

    /// Target URL when users click on the advertisement banner.
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    pub ad_banner_url: Option<String>,
    /// Copyright text displayed in the footer.
    pub copyright_notice: Option<String>,
    /// Additional custom links displayed in the community navigation.
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the community's Facebook page.
    pub facebook_url: Option<String>,
    /// URL to the small icon displayed in browser tabs and bookmarks.
    pub favicon_url: Option<String>,
    /// Link to the community's Flickr photo collection.
    pub flickr_url: Option<String>,
    /// URL to the logo image shown in the page footer.
    pub footer_logo_url: Option<String>,
    /// Link to the community's GitHub organization or repository.
    pub github_url: Option<String>,
    /// Link to the community's Instagram profile.
    pub instagram_url: Option<String>,
    /// Link to the community's `LinkedIn` page.
    pub linkedin_url: Option<String>,
    /// Instructions for creating new groups.
    pub new_group_details: Option<String>,
    /// URL to the Open Graph image used for link previews.
    pub og_image_url: Option<String>,
    /// Collection of photo URLs for community galleries or slideshows.
    pub photos_urls: Option<Vec<String>>,
    /// Link to the community's Slack workspace.
    pub slack_url: Option<String>,
    /// Link to the community's Twitter/X profile.
    pub twitter_url: Option<String>,
    /// Link to the community's main website.
    pub website_url: Option<String>,
    /// Link to the community's `WeChat` account or QR code.
    pub wechat_url: Option<String>,
    /// Link to the community's `YouTube` channel.
    pub youtube_url: Option<String>,
}

impl Community {
    /// Try to create a `Community` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json(data: &str) -> Result<Self> {
        let mut community: Community = serde_json::from_str(data)?;
        community.theme.palette = generate_palette(&community.theme.primary_color)?;
        Ok(community)
    }
}

// Other related types.

/// Theme information used to customize the selected layout.
///
/// Defines the primary color and derived color palette used throughout the community's
/// pages for consistent branding.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Theme {
    #[serde(default)]
    pub palette: Palette,
    pub primary_color: String,
}

/// Color palette mapping intensity levels (50-900) to hex color values.
///
/// Lower numbers represent lighter shades, higher numbers darker shades.
pub type Palette = BTreeMap<u32, String>;

// Helpers.

/// Generates a complete color palette from a single primary color.
///
/// Creates lighter and darker variants of the primary color to build palette with shades
/// from 50 (lightest) to 900 (darkest). Uses the palette crate for color manipulation.
fn generate_palette(color: &str) -> Result<Palette> {
    let color: Srgb<f32> = color.parse::<Srgb<u8>>()?.into();

    let to_hex = |c: Srgb<f32>| -> String { format!("#{:X}", Srgb::<u8>::from(c)) };
    let lighten = |f: f32| -> String { to_hex(color.lighten(f)) };
    let darken = |f: f32| -> String { to_hex(color.darken(f)) };

    let palette = BTreeMap::from([
        (50, lighten(0.95)),
        (100, lighten(0.9)),
        (300, lighten(0.5)),
        (500, to_hex(color)),
        (700, darken(0.2)),
        (900, darken(0.5)),
    ]);

    Ok(palette)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_colors_palette() {
        let primary_color = "#D62293";
        let palette = generate_palette(primary_color).unwrap();

        assert_eq!(palette[&50], "#FDF4FA");
        assert_eq!(palette[&100], "#FBE9F4");
        assert_eq!(palette[&300], "#EB90C9");
        assert_eq!(palette[&500], "#D62293");
        assert_eq!(palette[&700], "#AB1B76");
        assert_eq!(palette[&900], "#6B114A");
    }
}
