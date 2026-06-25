//! Templates and types for group member spotlights.

use askama::Template;
use chrono::{DateTime, Utc};
use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use uuid::Uuid;

use crate::{
    templates::{dashboard::group::members::GroupMember, helpers::user_initials},
    validation::{
        MAX_LEN_DESCRIPTION, MAX_LEN_L, MAX_LEN_M, image_url_opt, optional_trimmed_string,
        trimmed_non_empty, trimmed_non_empty_opt,
    },
};

/// Group dashboard spotlight management page.
#[derive(Debug, Clone, Template, Serialize, Deserialize)]
#[template(path = "dashboard/group/spotlights_list.html")]
pub(crate) struct ListPage {
    /// Whether the current user can manage spotlights.
    pub can_manage_spotlights: bool,
    /// Existing spotlights for the selected group.
    pub spotlights: Vec<GroupMemberSpotlight>,
    /// Group members eligible for spotlighting.
    pub members: Vec<GroupMember>,
}

/// Dashboard form payload for creating or updating a spotlight.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize, Validate)]
pub(crate) struct SpotlightInput {
    /// Highlighted group member.
    #[garde(skip)]
    pub user_id: Uuid,
    /// Story title.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_M))]
    pub title: String,
    /// Story body.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub story: String,
    /// Optional image URL for the story card.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(custom(image_url_opt))]
    pub image_url: Option<String>,
    /// Optional link to a deeper article, demo, video, or profile.
    #[serde(default, deserialize_with = "optional_trimmed_string")]
    #[garde(url, length(max = MAX_LEN_L), custom(trimmed_non_empty_opt))]
    pub link_url: Option<String>,
    /// Whether the spotlight should be emphasized.
    #[serde(default)]
    #[garde(skip)]
    pub featured: bool,
    /// Whether the spotlight is visible.
    #[serde(default = "default_published")]
    #[garde(skip)]
    pub published: bool,
}

/// Spotlight record with public member profile fields.
#[skip_serializing_none]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct GroupMemberSpotlight {
    /// Spotlight identifier.
    pub group_member_spotlight_id: Uuid,
    /// Group identifier.
    pub group_id: Uuid,
    /// Highlighted user identifier.
    pub user_id: Uuid,
    /// Creating user identifier.
    pub created_by: Uuid,
    /// Story title.
    pub title: String,
    /// Story body.
    pub story: String,
    /// Optional story image.
    pub image_url: Option<String>,
    /// Optional external link.
    pub link_url: Option<String>,
    /// Whether the story is emphasized.
    pub featured: bool,
    /// Whether the story is visible.
    pub published: bool,
    /// Creation time.
    #[serde(with = "chrono::serde::ts_seconds")]
    pub created_at: DateTime<Utc>,
    /// Last update time.
    #[serde(default, with = "chrono::serde::ts_seconds_option")]
    pub updated_at: Option<DateTime<Utc>>,

    /// Member username.
    pub username: String,
    /// Member display name.
    pub name: Option<String>,
    /// Member avatar URL.
    pub photo_url: Option<String>,
    /// Member job title.
    pub member_title: Option<String>,
    /// Member company.
    pub company: Option<String>,
    /// Member biography.
    pub bio: Option<String>,
}

impl GroupMemberSpotlight {
    /// Shareable profile path for the spotlighted member.
    pub(crate) fn profile_path(&self) -> String {
        format!("/profiles/{}", self.username)
    }

    /// Display label for the spotlighted member.
    pub(crate) fn member_display_name(&self) -> &str {
        self.name.as_deref().unwrap_or(&self.username)
    }
}

fn default_published() -> bool {
    true
}
