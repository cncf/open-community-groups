//! Image type definitions.

/// Image returned from a storage provider.
#[derive(Debug, Clone)]
pub(crate) struct Image {
    /// Image contents.
    pub bytes: Vec<u8>,
    /// MIME type set when the image was retrieved.
    pub content_type: String,
}

/// Image target defining expected dimensions.
///
/// The snake case name is the upload `target` field value shared with the
/// dashboard image fields.
#[derive(Clone, Copy, Debug, PartialEq, Eq, strum::Display, strum::EnumString)]
#[strum(serialize_all = "snake_case")]
pub(crate) enum ImageTarget {
    /// Community advertisement banner image.
    AdBanner,
    /// Square Open Badges artwork.
    Badge,
    /// Desktop banner image.
    Banner,
    /// Mobile banner image.
    BannerMobile,
    /// Square logo image.
    Logo,
    /// Open Graph preview image.
    OpenGraph,
}

impl ImageTarget {
    /// Returns the user-facing name used in validation messages.
    pub(crate) fn display_name(self) -> &'static str {
        match self {
            ImageTarget::AdBanner => "Advertisement banner",
            ImageTarget::Badge => "Badge",
            ImageTarget::Banner => "Banner",
            ImageTarget::BannerMobile => "Mobile banner",
            ImageTarget::Logo => "Logo",
            ImageTarget::OpenGraph => "Open Graph",
        }
    }

    /// Returns the required height in pixels for the target.
    pub(crate) const fn height(self) -> u32 {
        self.dimensions().1
    }

    /// Returns whether the target is served publicly and requires a raster format.
    pub(crate) fn requires_public_format(self) -> bool {
        matches!(self, ImageTarget::Badge | ImageTarget::OpenGraph)
    }

    /// Returns the required dimensions formatted for display, e.g. `2400 x 300`.
    pub(crate) fn size_text(self) -> String {
        let (width, height) = self.dimensions();
        format!("{width} x {height}")
    }

    /// Returns the required width in pixels for the target.
    pub(crate) const fn width(self) -> u32 {
        self.dimensions().0
    }

    /// Returns (width, height) for the target.
    const fn dimensions(self) -> (u32, u32) {
        match self {
            ImageTarget::AdBanner => (2400, 300),
            ImageTarget::Badge => (512, 512),
            ImageTarget::Banner => (2428, 192),
            ImageTarget::BannerMobile => (1220, 192),
            ImageTarget::Logo => (360, 360),
            ImageTarget::OpenGraph => (1200, 630),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use super::ImageTarget;

    #[test]
    fn test_image_target_round_trips_upload_names() {
        for (target, name) in [
            (ImageTarget::AdBanner, "ad_banner"),
            (ImageTarget::Badge, "badge"),
            (ImageTarget::Banner, "banner"),
            (ImageTarget::BannerMobile, "banner_mobile"),
            (ImageTarget::Logo, "logo"),
            (ImageTarget::OpenGraph, "open_graph"),
        ] {
            assert_eq!(ImageTarget::from_str(name).unwrap(), target, "{name}");
            assert_eq!(target.to_string(), name, "{name}");
        }
    }

    #[test]
    fn test_image_target_from_str_rejects_unknown_names() {
        assert!(ImageTarget::from_str("unknown").is_err());
    }

    #[test]
    fn test_image_target_size_text_formats_dimensions() {
        // Check the accessors and display text share the target dimensions
        assert_eq!(ImageTarget::AdBanner.width(), 2400);
        assert_eq!(ImageTarget::AdBanner.height(), 300);
        assert_eq!(ImageTarget::AdBanner.size_text(), "2400 x 300");
        assert_eq!(ImageTarget::OpenGraph.size_text(), "1200 x 630");
    }
}
