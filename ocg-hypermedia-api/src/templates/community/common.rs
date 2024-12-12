//! This module defines some templates and types used in some pages of the
//! community site.

use std::collections::BTreeMap;

use anyhow::Result;
use palette::{Darken, Lighten, Srgb};
use serde::{Deserialize, Serialize};
use tracing::instrument;

/// Community information used in some community pages.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Community {
    pub description: String,
    pub display_name: String,
    pub header_logo_url: String,
    pub name: String,
    pub theme: Theme,
    pub title: String,

    pub ad_banner_link_url: Option<String>,
    pub ad_banner_url: Option<String>,
    pub copyright_notice: Option<String>,
    pub extra_links: Option<BTreeMap<String, String>>,
    pub facebook_url: Option<String>,
    pub flickr_url: Option<String>,
    pub footer_logo_url: Option<String>,
    pub github_url: Option<String>,
    pub instagram_url: Option<String>,
    pub linkedin_url: Option<String>,
    pub new_group_details: Option<String>,
    pub photos_urls: Option<Vec<String>>,
    pub slack_url: Option<String>,
    pub twitter_url: Option<String>,
    pub website_url: Option<String>,
    pub wechat_url: Option<String>,
    pub youtube_url: Option<String>,
}

impl Community {
    /// Try to create a `Community` instance from a JSON string.
    #[instrument(skip_all, err)]
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let mut community: Community = serde_json::from_str(data)?;
        community.theme.palette = generate_palette(&community.theme.primary_color)?;
        Ok(community)
    }
}

/// Theme information used to customize the selected layout.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Theme {
    #[serde(default)]
    pub palette: Palette,
    pub primary_color: String,
}

/// Theme colors palette.
type Palette = BTreeMap<u32, String>;

/// Event kind (in-person, virtual or hybrid).
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum EventKind {
    Hybrid,
    #[default]
    InPerson,
    Virtual,
}

impl std::fmt::Display for EventKind {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            EventKind::Hybrid => write!(f, "hybrid"),
            EventKind::InPerson => write!(f, "in-person"),
            EventKind::Virtual => write!(f, "virtual"),
        }
    }
}

/// Generate a palette from the provided color.
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
