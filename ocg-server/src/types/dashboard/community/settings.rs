//! Community dashboard settings types.

use std::collections::BTreeMap;

use garde::Validate;
use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

use crate::validation::{
    MAX_LEN_DESCRIPTION, MAX_LEN_DISPLAY_NAME, MAX_LEN_L, image_url, image_url_opt, image_url_vec,
    trimmed_non_empty, trimmed_non_empty_opt, url_map_values, web_url_opt,
};

/// Community update form data.
#[skip_serializing_none]
#[derive(Debug, Clone, Default, Serialize, Deserialize, Validate)]
pub(crate) struct CommunityUpdate {
    /// URL to the community banner image optimized for mobile devices.
    #[garde(custom(image_url))]
    pub banner_mobile_url: String,
    /// URL to the community banner image.
    #[garde(custom(image_url))]
    pub banner_url: String,
    /// Brief description of the community's purpose or focus.
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DESCRIPTION))]
    pub description: String,
    /// Human-readable name shown in the UI (e.g., "CNCF").
    #[garde(custom(trimmed_non_empty), length(max = MAX_LEN_DISPLAY_NAME))]
    pub display_name: String,
    /// Whether group team management is restricted to community roles.
    #[garde(skip)]
    pub group_team_management_restricted: bool,
    /// URL to the logo image.
    #[garde(custom(image_url))]
    pub logo_url: String,

    /// Target URL when users click on the advertisement banner.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub ad_banner_link_url: Option<String>,
    /// URL to the advertisement banner image.
    #[garde(custom(image_url_opt))]
    pub ad_banner_url: Option<String>,
    /// URL to the community banner image shown in dark mode in place of
    /// `banner_url`.
    #[garde(custom(image_url_opt))]
    pub banner_dark_url: Option<String>,
    /// URL to the community mobile banner image shown in dark mode in place
    /// of `banner_mobile_url`.
    #[garde(custom(image_url_opt))]
    pub banner_mobile_dark_url: Option<String>,
    /// Link to the community's Bluesky profile.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub bluesky_url: Option<String>,
    /// Additional custom links displayed in the community navigation.
    #[garde(custom(url_map_values))]
    pub extra_links: Option<BTreeMap<String, String>>,
    /// Link to the community's Facebook page.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub facebook_url: Option<String>,
    /// Link to the community's Flickr photo collection.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub flickr_url: Option<String>,
    /// Link to the community's GitHub organization or repository.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub github_url: Option<String>,
    /// Link to the community's Instagram profile.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub instagram_url: Option<String>,
    /// Link to the community's `LinkedIn` page.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub linkedin_url: Option<String>,
    /// URL to the logo image shown in dark mode in place of `logo_url`.
    #[garde(custom(image_url_opt))]
    pub logo_dark_url: Option<String>,
    /// Instructions for creating new groups.
    #[garde(custom(trimmed_non_empty_opt), length(max = MAX_LEN_DESCRIPTION))]
    pub new_group_details: Option<String>,
    /// URL to the community's Open Graph image.
    #[garde(custom(image_url_opt))]
    pub og_image_url: Option<String>,
    /// Collection of photo URLs for community galleries or slideshows.
    #[garde(custom(image_url_vec))]
    pub photos_urls: Option<Vec<String>>,
    /// Link to the community's Slack workspace.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub slack_url: Option<String>,
    /// Link to the community's Twitter/X profile.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub twitter_url: Option<String>,
    /// Link to the community's main website.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub website_url: Option<String>,
    /// Link to the community's `WeChat` account or QR code.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub wechat_url: Option<String>,
    /// Link to the community's `YouTube` channel.
    #[garde(custom(web_url_opt), length(max = MAX_LEN_L))]
    pub youtube_url: Option<String>,
}

#[cfg(test)]
mod tests {
    use garde::Validate;

    use super::CommunityUpdate;

    #[test]
    fn test_community_update_validation_accepts_missing_dark_images() {
        assert!(sample_community_update().validate().is_ok());
    }

    #[test]
    fn test_community_update_validation_rejects_invalid_dark_images() {
        // Setup cases: (case, community, invalid field)
        let cases = [
            (
                "invalid dark banner URL",
                CommunityUpdate {
                    banner_dark_url: Some("not-a-url".to_string()),
                    ..sample_community_update()
                },
                "banner_dark_url",
            ),
            (
                "invalid dark mobile banner URL",
                CommunityUpdate {
                    banner_mobile_dark_url: Some("not-a-url".to_string()),
                    ..sample_community_update()
                },
                "banner_mobile_dark_url",
            ),
            (
                "blank dark logo URL",
                CommunityUpdate {
                    logo_dark_url: Some("  ".to_string()),
                    ..sample_community_update()
                },
                "logo_dark_url",
            ),
        ];

        for (case, community, field) in cases {
            // Check only the dark image field is rejected
            let report = community.validate().expect_err(case);
            let fields: Vec<String> = report.iter().map(|(path, _)| path.to_string()).collect();
            assert_eq!(fields, [field], "{case}");
        }
    }

    // Helpers.

    /// Returns a valid community update without dark images.
    fn sample_community_update() -> CommunityUpdate {
        CommunityUpdate {
            banner_mobile_url: "https://example.test/banner-mobile.png".to_string(),
            banner_url: "https://example.test/banner.png".to_string(),
            description: "Community description".to_string(),
            display_name: "Community".to_string(),
            logo_url: "https://example.test/logo.png".to_string(),
            ..CommunityUpdate::default()
        }
    }
}
