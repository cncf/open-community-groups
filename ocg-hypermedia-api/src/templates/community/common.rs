//! This module defines some templates and types used in some pages of the
//! community site.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Community information used in some community pages.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Community {
    pub display_name: String,
    pub header_logo_url: String,
    pub title: String,
    pub description: String,

    pub ad_banner_link_url: Option<String>,
    pub ad_banner_url: Option<String>,
    pub copyright_notice: Option<String>,
    pub extra_links: Option<BTreeMap<String, String>>,
    pub facebook_url: Option<String>,
    pub flickr_url: Option<String>,
    pub footer_logo_url: Option<String>,
    pub github_url: Option<String>,
    pub homepage_url: Option<String>,
    pub instagram_url: Option<String>,
    pub linkedin_url: Option<String>,
    pub new_group_details: Option<String>,
    pub photos_urls: Option<Vec<String>>,
    pub slack_url: Option<String>,
    pub twitter_url: Option<String>,
    pub wechat_url: Option<String>,
    pub youtube_url: Option<String>,
}

impl Community {
    /// Try to create a `Community` instance from a JSON string.
    pub(crate) fn try_from_json(data: &str) -> Result<Self> {
        let mut community: Community = serde_json::from_str(data)?;

        // Convert markdown content in some fields to HTML
        community.description = markdown::to_html(&community.description);
        if let Some(copyright_notice) = &community.copyright_notice {
            community.copyright_notice = Some(markdown::to_html(copyright_notice));
        }
        if let Some(new_group_details) = &community.new_group_details {
            community.new_group_details = Some(markdown::to_html(new_group_details));
        }

        Ok(community)
    }
}
