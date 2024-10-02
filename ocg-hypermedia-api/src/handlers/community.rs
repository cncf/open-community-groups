//! This module defines the HTTP handlers for the community site.

use super::extractor::CommunityId;
use crate::db::DynDB;
use anyhow::{Error, Result};
use askama_axum::IntoResponse;
use axum::{
    extract::{Query, Request, State},
    http::StatusCode,
};
use std::{collections::HashMap, fmt::Debug};
use templates::{Explore, ExploreEvents, ExploreGroups, Home};
use tracing::error;

/// Handler that returns the home page.
pub(crate) async fn home(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .get_community_home_data(community_id)
        .await
        .map_err(internal_error)?;
    let template = Home {
        params,
        path: request.uri().path().to_string(),
        ..Home::try_from(json_data).map_err(internal_error)?
    };

    Ok(template)
}

/// Handler that returns the explore page.
pub(crate) async fn explore(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
    Query(params): Query<HashMap<String, String>>,
    request: Request,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .get_community_explore_data(community_id)
        .await
        .map_err(internal_error)?;
    let template = Explore {
        params,
        path: request.uri().path().to_string(),
        ..Explore::try_from(json_data).map_err(internal_error)?
    };

    Ok(template)
}

/// Handler that returns the explore events section.
pub(crate) async fn explore_events(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .search_community_events(community_id)
        .await
        .map_err(internal_error)?;
    let template = ExploreEvents::try_from(json_data).map_err(internal_error)?;

    Ok(template)
}

/// Handler that returns the explore groups section.
pub(crate) async fn explore_groups(
    State(db): State<DynDB>,
    CommunityId(community_id): CommunityId,
) -> Result<impl IntoResponse, StatusCode> {
    let json_data = db
        .search_community_groups(community_id)
        .await
        .map_err(internal_error)?;
    let template = ExploreGroups::try_from(json_data).map_err(internal_error)?;

    Ok(template)
}

/// Helper for mapping any error into a `500 Internal Server Error` response.
#[allow(clippy::needless_pass_by_value)]
fn internal_error<E>(err: E) -> StatusCode
where
    E: Into<Error> + Debug,
{
    error!(?err);
    StatusCode::INTERNAL_SERVER_ERROR
}

pub(crate) mod templates {
    use crate::db::JsonString;
    use anyhow::{Context, Error, Result};
    use askama::Template;
    use chrono::{DateTime, Utc};
    use serde::{Deserialize, Serialize};
    use std::collections::{BTreeMap, HashMap};

    /// Home page template.
    #[derive(Debug, Clone, Template, Serialize, Deserialize)]
    #[template(path = "community/home.html")]
    pub(crate) struct Home {
        pub community: Community,
        #[serde(default)]
        pub params: HashMap<String, String>,
        #[serde(default)]
        pub path: String,
        pub recently_added_groups: Vec<HomeGroup>,
        pub upcoming_in_person_events: Vec<HomeEvent>,
        pub upcoming_online_events: Vec<HomeEvent>,
    }

    impl TryFrom<JsonString> for Home {
        type Error = Error;

        fn try_from(json_data: JsonString) -> Result<Self> {
            let mut home: Home = serde_json::from_str(&json_data)
                .context("error deserializing home template json data")?;

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
    pub(crate) struct HomeEvent {
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
    pub(crate) struct HomeGroup {
        pub name: String,
        pub region_name: String,
        pub slug: String,

        pub city: Option<String>,
        pub country: Option<String>,
        pub icon_url: Option<String>,
        pub state: Option<String>,
    }

    /// Explore page template.
    #[derive(Debug, Clone, Template, Serialize, Deserialize)]
    #[template(path = "community/explore.html")]
    pub(crate) struct Explore {
        pub community: Community,
        #[serde(default)]
        pub params: HashMap<String, String>,
        #[serde(default)]
        pub path: String,
    }

    impl TryFrom<JsonString> for Explore {
        type Error = Error;

        fn try_from(json_data: JsonString) -> Result<Self> {
            let explore: Explore = serde_json::from_str(&json_data)
                .context("error deserializing explore template json data")?;

            Ok(explore)
        }
    }

    /// Explore events section template.
    #[derive(Debug, Clone, Template, Serialize, Deserialize)]
    #[template(path = "community/explore_events.html")]
    pub(crate) struct ExploreEvents {
        pub events: Vec<ExploreEvent>,
    }

    impl TryFrom<JsonString> for ExploreEvents {
        type Error = Error;

        fn try_from(json_data: JsonString) -> Result<Self> {
            let mut explore_events = ExploreEvents {
                events: serde_json::from_str(&json_data)
                    .context("error deserializing events json data")?,
            };

            // Convert markdown content in some fields to HTML
            for event in &mut explore_events.events {
                event.description = markdown::to_html(&event.description);
            }

            Ok(explore_events)
        }
    }

    /// Event information used in the community explore page.
    #[derive(Debug, Clone, Default, Serialize, Deserialize)]
    pub(crate) struct ExploreEvent {
        pub cancelled: bool,
        pub description: String,
        pub event_kind_id: String,
        pub group_name: String,
        pub group_slug: String,
        pub postponed: bool,
        pub slug: String,
        #[serde(with = "chrono::serde::ts_seconds")]
        pub starts_at: DateTime<Utc>,
        pub title: String,

        pub city: Option<String>,
        pub country: Option<String>,
        pub icon_url: Option<String>,
        pub state: Option<String>,
        pub venue: Option<String>,
    }

    impl ExploreEvent {
        /// Returns the location of the event.
        pub fn location(&self) -> Option<String> {
            let mut location = String::new();
            if let Some(venue) = &self.venue {
                location.push_str(venue);
            }
            if let Some(city) = &self.city {
                if !location.is_empty() {
                    location.push_str(", ");
                }
                location.push_str(city);
            }
            if let Some(state) = &self.state {
                if !location.is_empty() {
                    location.push_str(", ");
                }
                location.push_str(state);
            }
            if let Some(country) = &self.country {
                if !location.is_empty() {
                    location.push_str(", ");
                }
                location.push_str(country);
            }
            if location.is_empty() {
                None
            } else {
                Some(location)
            }
        }
    }

    /// Explore groups section template.
    #[derive(Debug, Clone, Template, Serialize, Deserialize)]
    #[template(path = "community/explore_groups.html")]
    pub(crate) struct ExploreGroups {
        pub groups: Vec<ExploreGroup>,
    }

    impl TryFrom<JsonString> for ExploreGroups {
        type Error = Error;

        fn try_from(json_data: JsonString) -> Result<Self> {
            let mut explore_groups = ExploreGroups {
                groups: serde_json::from_str(&json_data)
                    .context("error deserializing groups json data")?,
            };

            // Convert markdown content in some fields to HTML
            for group in &mut explore_groups.groups {
                group.description = markdown::to_html(&group.description);
            }

            Ok(explore_groups)
        }
    }

    /// Group information used in the community explore page.
    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub(crate) struct ExploreGroup {
        pub description: String,
        pub name: String,
        pub region_name: String,
        pub slug: String,

        pub city: Option<String>,
        pub country: Option<String>,
        pub icon_url: Option<String>,
        pub state: Option<String>,
    }

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

    #[cfg(test)]
    mod tests {
        use super::ExploreEvent;

        #[test]
        fn explore_event_location() {
            let event = ExploreEvent {
                city: Some("City".to_string()),
                country: Some("Country".to_string()),
                state: Some("State".to_string()),
                venue: Some("Venue".to_string()),
                ..Default::default()
            };
            assert_eq!(
                event.location(),
                Some("Venue, City, State, Country".to_string())
            );

            let event = ExploreEvent {
                city: Some("City".to_string()),
                country: Some("Country".to_string()),
                state: Some("State".to_string()),
                ..Default::default()
            };
            assert_eq!(event.location(), Some("City, State, Country".to_string()));

            let event = ExploreEvent {
                country: Some("Country".to_string()),
                venue: Some("Venue".to_string()),
                ..Default::default()
            };
            assert_eq!(event.location(), Some("Venue, Country".to_string()));

            let event = ExploreEvent {
                city: Some("City".to_string()),
                venue: Some("Venue".to_string()),
                ..Default::default()
            };
            assert_eq!(event.location(), Some("Venue, City".to_string()));

            let event = ExploreEvent::default();
            assert_eq!(event.location(), None);
        }
    }
}
