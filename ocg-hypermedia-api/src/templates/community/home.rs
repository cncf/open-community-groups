//! This module defines some templates and types used in the home page of the
//! community site.

use super::common::Community;
use crate::db::JsonString;
use anyhow::{Context, Error, Result};
use askama::Template;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Home index page template.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "community/home/index.html")]
pub(crate) struct Index {
    pub community: Community,
    #[serde(default)]
    pub params: HashMap<String, String>,
    #[serde(default)]
    pub path: String,
    pub recently_added_groups: Vec<Group>,
    pub upcoming_in_person_events: Vec<Event>,
    pub upcoming_online_events: Vec<Event>,
}

impl TryFrom<JsonString> for Index {
    type Error = Error;

    fn try_from(json_data: JsonString) -> Result<Self> {
        let mut home: Index = serde_json::from_str(&json_data)
            .context("error deserializing home index template json data")?;

        // Convert markdown content in some fields to HTML
        home.community.description = markdown::to_html(&home.community.description);
        if let Some(copyright_notice) = &home.community.copyright_notice {
            home.community.copyright_notice = Some(markdown::to_html(copyright_notice));
        }
        if let Some(new_group_details) = &home.community.new_group_details {
            home.community.new_group_details = Some(markdown::to_html(new_group_details));
        }

        Ok(home)
    }
}

/// Event information used in the community home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Event {
    pub group_name: String,
    pub group_slug: String,
    pub slug: String,
    #[serde(with = "chrono::serde::ts_seconds")]
    pub starts_at: DateTime<Utc>,
    pub title: String,

    pub city: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}

/// Group information used in the community home page.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Group {
    pub name: String,
    pub region_name: String,
    pub slug: String,

    pub city: Option<String>,
    pub country: Option<String>,
    pub icon_url: Option<String>,
    pub state: Option<String>,
}
