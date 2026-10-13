//! UTM attribution types shared by event page view tracking and group settings.

use serde::Deserialize;

use crate::validation::is_valid_utm_value;

/// Normalized UTM parameters a view is attributed to.
///
/// A view is attributed to a source, a campaign, or both. Every present value
/// has the format accepted by the database.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) struct UtmParams {
    /// Normalized `utm_campaign` value.
    campaign: Option<String>,
    /// Normalized `utm_medium` value.
    medium: Option<String>,
    /// Normalized `utm_source` value.
    source: Option<String>,
}

impl UtmParams {
    /// Creates normalized UTM parameters from raw values.
    ///
    /// Values are trimmed and lowercased, and blank values are treated as
    /// missing. Returns `None` when any present value has an unsupported
    /// format, or when neither a source nor a campaign remains, as views are
    /// only attributed to a source or a campaign.
    pub(crate) fn new(
        campaign: Option<&str>,
        medium: Option<&str>,
        source: Option<&str>,
    ) -> Option<Self> {
        // Normalize the values, treating blank ones as missing
        let campaign = normalize_utm_value(campaign);
        let medium = normalize_utm_value(medium);
        let source = normalize_utm_value(source);

        // Drop the attribution when any present value has an unsupported format
        if [&campaign, &medium, &source]
            .into_iter()
            .flatten()
            .any(|value| !is_valid_utm_value(value))
        {
            return None;
        }

        // Require a source or a campaign to attribute the view to
        if campaign.is_none() && source.is_none() {
            return None;
        }

        Some(Self {
            campaign,
            medium,
            source,
        })
    }

    /// Returns the normalized `utm_campaign` value.
    pub(crate) fn campaign(&self) -> Option<&str> {
        self.campaign.as_deref()
    }

    /// Returns the normalized `utm_medium` value.
    pub(crate) fn medium(&self) -> Option<&str> {
        self.medium.as_deref()
    }

    /// Returns the normalized `utm_source` value.
    pub(crate) fn source(&self) -> Option<&str> {
        self.source.as_deref()
    }
}

/// UTM values accepted for the page views of an event.
#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
pub(crate) struct EventUtmAllowlist {
    /// Accepted `utm_campaign` values.
    pub campaigns: Vec<String>,
    /// Accepted `utm_medium` values, including the default ones every group
    /// accepts.
    pub mediums: Vec<String>,
    /// Accepted `utm_source` values.
    pub sources: Vec<String>,
}

impl EventUtmAllowlist {
    /// Returns whether every UTM parameter present is accepted.
    pub(crate) fn permits(&self, utm: &UtmParams) -> bool {
        let accepts = |values: &[String], value: Option<&str>| {
            value.is_none_or(|value| values.iter().any(|v| v == value))
        };

        accepts(&self.campaigns, utm.campaign())
            && accepts(&self.mediums, utm.medium())
            && accepts(&self.sources, utm.source())
    }
}

/// UTM values a group defines for the page views of its events.
#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
pub(crate) struct GroupUtmSettings {
    /// Accepted `utm_campaign` values.
    pub campaigns: Vec<String>,
    /// Extra `utm_medium` values accepted in addition to the default ones.
    pub mediums: Vec<String>,
    /// Accepted `utm_source` values.
    pub sources: Vec<String>,
}

/// Trims and lowercases a raw UTM value, returning `None` when it is blank.
fn normalize_utm_value(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_ascii_lowercase)
}

#[cfg(test)]
mod tests {
    use crate::validation::MAX_LEN_UTM_VALUE;

    use super::*;

    #[test]
    fn test_event_utm_allowlist_permits_accepted_values() {
        // Setup the allowlist
        let allowlist = sample_event_utm_allowlist();

        // Check present parameters are all accepted
        assert!(allowlist.permits(&UtmParams::new(None, None, Some("newsletter")).unwrap()));
        assert!(allowlist.permits(&UtmParams::new(Some("spring-launch"), None, None).unwrap()));
        assert!(allowlist.permits(
            &UtmParams::new(Some("spring-launch"), Some("email"), Some("newsletter")).unwrap()
        ));
    }

    #[test]
    fn test_event_utm_allowlist_permits_rejects_unknown_values() {
        // Setup the allowlist
        let allowlist = sample_event_utm_allowlist();

        // Check any unknown parameter rejects the attribution
        assert!(!allowlist.permits(&UtmParams::new(None, None, Some("unknown")).unwrap()));
        assert!(
            !allowlist.permits(&UtmParams::new(Some("unknown"), None, Some("newsletter")).unwrap())
        );
        assert!(
            !allowlist.permits(&UtmParams::new(None, Some("unknown"), Some("newsletter")).unwrap())
        );
        assert!(
            !EventUtmAllowlist::default()
                .permits(&UtmParams::new(None, None, Some("newsletter")).unwrap())
        );
    }

    #[test]
    fn test_utm_params_new_accepts_campaign_without_source() {
        assert_eq!(
            UtmParams::new(Some("spring-launch"), Some("email"), None),
            Some(UtmParams {
                campaign: Some("spring-launch".to_string()),
                medium: Some("email".to_string()),
                source: None,
            })
        );
    }

    #[test]
    fn test_utm_params_new_normalizes_values() {
        // Normalize raw values with surrounding whitespace and uppercase letters
        let utm = UtmParams::new(Some(" Spring-Launch "), Some("  "), Some("\tNewsletter\n"));

        // Check values are trimmed, lowercased, and blank values are missing
        assert_eq!(
            utm,
            Some(UtmParams {
                campaign: Some("spring-launch".to_string()),
                medium: None,
                source: Some("newsletter".to_string()),
            })
        );
    }

    #[test]
    fn test_utm_params_new_rejects_invalid_values() {
        // Check unsupported characters drop the whole attribution
        assert_eq!(
            UtmParams::new(Some("spring launch"), None, Some("newsletter")),
            None
        );
        assert_eq!(
            UtmParams::new(None, Some("e-mail!"), Some("newsletter")),
            None
        );
        assert_eq!(UtmParams::new(None, None, Some("news\u{0}letter")), None);

        // Check values longer than the database limit drop the whole attribution
        let long_value = "a".repeat(MAX_LEN_UTM_VALUE + 1);
        assert_eq!(UtmParams::new(None, None, Some(&long_value)), None);
        assert!(UtmParams::new(None, None, Some(&long_value[1..])).is_some());
    }

    #[test]
    fn test_utm_params_new_requires_source_or_campaign() {
        assert_eq!(UtmParams::new(None, Some("email"), None), None);
        assert_eq!(UtmParams::new(Some(" "), Some("email"), Some("")), None);
    }

    // Helpers.

    /// Returns a sample allowlist accepting one value per parameter.
    fn sample_event_utm_allowlist() -> EventUtmAllowlist {
        EventUtmAllowlist {
            campaigns: vec!["spring-launch".to_string()],
            mediums: vec!["email".to_string()],
            sources: vec!["newsletter".to_string()],
        }
    }
}
