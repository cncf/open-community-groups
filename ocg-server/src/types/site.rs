//! Site-related types used across the application.

use std::collections::BTreeMap;

use anyhow::Result;
use palette::{Darken, Lighten, Srgb};
use serde::{Deserialize, Serialize};
use tracing::instrument;
use uuid::Uuid;

// Site types.

/// Statistics for the site home page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[allow(dead_code)]
pub struct SiteHomeStats {
    /// Number of active communities.
    pub communities: usize,
    /// Number of published events.
    pub events: usize,
    /// Number of event attendees.
    pub events_attendees: usize,
    /// Number of active groups.
    pub groups: usize,
    /// Number of group members.
    pub groups_members: usize,
}

#[allow(dead_code)]
impl SiteHomeStats {
    /// Try to create a `SiteHomeStats` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json(data: &str) -> Result<Self> {
        Ok(serde_json::from_str(data)?)
    }
}

/// Global site settings.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SiteSettings {
    /// Brief description of the site.
    pub description: String,
    /// Unique identifier for the site.
    pub site_id: Uuid,
    /// Visual theme configuration including primary color and palette.
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

impl SiteSettings {
    /// Try to create a `SiteSettings` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub fn try_from_json(data: &str) -> Result<Self> {
        let mut site: SiteSettings = serde_json::from_str(data)?;
        site.theme.palette = generate_palette(&site.theme.primary_color)?;
        Ok(site)
    }
}

// Other related types.

/// Theme information used to customize the site layout.
///
/// Defines the primary color and derived color palette used throughout the site's
/// pages for consistent branding.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
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
        (200, lighten(0.75)),
        (300, lighten(0.5)),
        (400, lighten(0.25)),
        (500, to_hex(color)),
        (600, darken(0.1)),
        (700, darken(0.2)),
        (800, darken(0.35)),
        (900, darken(0.5)),
        (950, darken(0.65)),
    ]);

    Ok(palette)
}

// Tests.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_colors_palette() {
        let primary_color = "#D62293";
        let palette = generate_palette(primary_color).unwrap();

        assert_eq!(palette[&50], "#FDF4FA");
        assert_eq!(palette[&100], "#FBE9F4");
        assert_eq!(palette[&200], "#F5C8E4");
        assert_eq!(palette[&300], "#EB90C9");
        assert_eq!(palette[&400], "#E059AE");
        assert_eq!(palette[&500], "#D62293");
        assert_eq!(palette[&600], "#C11F84");
        assert_eq!(palette[&700], "#AB1B76");
        assert_eq!(palette[&800], "#8B1660");
        assert_eq!(palette[&900], "#6B114A");
        assert_eq!(palette[&950], "#4B0C33");
    }

    #[test]
    fn test_generate_palette_returns_error_for_invalid_color() {
        let invalid_color = "#GGGGGG";

        assert!(generate_palette(invalid_color).is_err());
    }
}
