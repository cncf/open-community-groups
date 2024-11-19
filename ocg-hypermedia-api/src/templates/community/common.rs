//! This module defines some templates and types used in some pages of the
//! community site.

use std::collections::BTreeMap;

use anyhow::Result;
use serde::{Deserialize, Serialize};

/// Community information used in some community pages.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Community {
    pub description: String,
    pub display_name: String,
    pub header_logo_url: String,
    pub name: String,
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
    pub theme: Option<Theme>,
    pub twitter_url: Option<String>,
    pub website_url: Option<String>,
    pub wechat_url: Option<String>,
    pub youtube_url: Option<String>,
}

impl Community {
    /// Try to create a `Community` instance from a JSON string.
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let community: Community = serde_json::from_str(data)?;
        Ok(community)
    }
}

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

/// Theme information used to customize the selected layout.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Theme {
    pub primary_color: String,
}
