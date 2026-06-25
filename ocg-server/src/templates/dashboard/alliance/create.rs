//! Templates for creating alliances from the alliance dashboard.

use askama::Template;
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::validation::{
    MAX_LEN_DESCRIPTION, MAX_LEN_DISPLAY_NAME, MAX_LEN_L, MAX_LEN_S, image_url, trimmed_non_empty,
    trimmed_non_empty_opt,
};

/// Alliance create form template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/alliance/create.html")]
pub(crate) struct Page;

/// Alliance create form data.
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct AllianceCreate {
    /// URL to the alliance banner image optimized for mobile devices.
    #[garde(custom(image_url))]
    pub banner_mobile_url: String,
    /// URL to the alliance banner image.
    #[garde(custom(image_url))]
    pub banner_url: String,
    /// Brief description of the alliance's purpose or focus.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Human-readable name shown in the UI.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DISPLAY_NAME))]
    pub display_name: String,
    /// URL to the logo image.
    #[garde(custom(image_url))]
    pub logo_url: String,
    /// URL-friendly alliance slug used in public paths.
    #[garde(custom(valid_alliance_slug), length(max = MAX_LEN_S))]
    pub name: String,
    /// Link to the alliance's main website.
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty_opt))]
    pub website_url: Option<String>,
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn valid_alliance_slug(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    let value = value.as_ref();
    if value.is_empty() {
        return Err(garde::Error::new("slug cannot be empty"));
    }
    if value.trim() != value {
        return Err(garde::Error::new(
            "slug cannot contain leading or trailing spaces",
        ));
    }
    if !value
        .chars()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-')
    {
        return Err(garde::Error::new(
            "slug can only contain lowercase letters, numbers, and hyphens",
        ));
    }
    if value.starts_with('-') || value.ends_with('-') || value.contains("--") {
        return Err(garde::Error::new(
            "slug must not start, end, or repeat hyphens",
        ));
    }

    Ok(())
}
