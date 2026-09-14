//! Upload validation for images: format detection, extension checks, SVG
//! sanitization, and target dimension requirements.

use std::{borrow::Cow, io::Cursor, str::FromStr};

use anyhow::{Context, Result, anyhow};
use image::{ImageFormat, ImageReader};
use quick_xml::{Reader, XmlVersion, events::Event};

use super::{OPEN_GRAPH_IMAGE_HEIGHT, OPEN_GRAPH_IMAGE_WIDTH};

#[cfg(test)]
mod tests;

/// Validates an uploaded image and returns the metadata needed to store it.
///
/// The extension must match the detected format, public credential and Open
/// Graph targets require a raster format, and raster targets must match their
/// exact dimensions.
pub(crate) fn validate_image_upload(
    file_name: &str,
    bytes: &[u8],
    target: Option<ImageTarget>,
) -> Result<ValidatedImage, ImageValidationError> {
    // Detect the image format and check the extension matches
    let extension = image_extension(file_name).map_err(ImageValidationError::Unsupported)?;
    let format = detect_image_format(bytes, extension.as_ref())
        .map_err(ImageValidationError::Unsupported)?;
    if !extension_matches(&format, extension.as_ref()) {
        return Err(ImageValidationError::ExtensionMismatch);
    }

    // Validate target-specific image requirements
    if let Some(target) = target {
        // Require a raster format for public credential and Open Graph images
        if target.requires_public_format() && !format.is_public_supported() {
            return Err(ImageValidationError::PublicFormatRequired {
                target_name: target.display_name(),
            });
        }

        // Validate target dimensions when the format supports dimension checks
        if !matches!(format, SupportedImageFormat::Svg)
            && let Err(err) = validate_image_dimensions(bytes, target)
        {
            return Err(ImageValidationError::Dimensions(err.to_string()));
        }
    }

    Ok(ValidatedImage {
        content_type: format.mime_type(),
        extension: extension.into_owned(),
    })
}

/// Validates that the image dimensions match the target requirements.
pub(crate) fn validate_image_dimensions(bytes: &[u8], target: ImageTarget) -> Result<()> {
    let (expected_width, expected_height) = target.dimensions();
    let reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .context("failed to detect image format")?;
    let (width, height) = reader.into_dimensions().context("failed to read dimensions")?;

    if width != expected_width || height != expected_height {
        return Err(anyhow!(
            "image dimensions {width}x{height} do not match required {expected_width}x{expected_height}"
        ));
    }

    Ok(())
}

// Types.

/// Image target defining expected dimensions.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ImageTarget {
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
    /// Returns (width, height) for the target.
    pub(crate) fn dimensions(self) -> (u32, u32) {
        match self {
            ImageTarget::Badge => (512, 512),
            ImageTarget::Banner => (2428, 192),
            ImageTarget::BannerMobile => (1220, 192),
            ImageTarget::Logo => (360, 360),
            ImageTarget::OpenGraph => (OPEN_GRAPH_IMAGE_WIDTH, OPEN_GRAPH_IMAGE_HEIGHT),
        }
    }

    /// Returns the user-facing name used in validation messages.
    fn display_name(self) -> &'static str {
        match self {
            ImageTarget::Badge => "Badge",
            ImageTarget::Banner => "Banner",
            ImageTarget::BannerMobile => "Mobile banner",
            ImageTarget::Logo => "Logo",
            ImageTarget::OpenGraph => "Open Graph",
        }
    }

    /// Returns whether the target is served publicly and requires a raster format.
    fn requires_public_format(self) -> bool {
        matches!(self, ImageTarget::Badge | ImageTarget::OpenGraph)
    }
}

impl FromStr for ImageTarget {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s {
            "badge" => Ok(ImageTarget::Badge),
            "banner" => Ok(ImageTarget::Banner),
            "banner_mobile" => Ok(ImageTarget::BannerMobile),
            "logo" => Ok(ImageTarget::Logo),
            "open_graph" => Ok(ImageTarget::OpenGraph),
            _ => Err(anyhow!("unknown image target: {s}")),
        }
    }
}

/// Reasons an uploaded image is rejected.
#[derive(Debug, thiserror::Error)]
pub(crate) enum ImageValidationError {
    /// The image dimensions do not match the target requirements.
    #[error("{0}")]
    Dimensions(String),
    /// The file extension does not match the detected image format.
    #[error("file extension does not match detected image format")]
    ExtensionMismatch,
    /// The target only accepts raster formats suitable for public embedding.
    #[error("{target_name} images must be PNG, JPEG, or WebP")]
    PublicFormatRequired {
        /// User-facing target name.
        target_name: &'static str,
    },
    /// The file has no extension or its format is not supported.
    #[error(transparent)]
    Unsupported(anyhow::Error),
}

/// Supported image formats accepted by the upload endpoint.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum SupportedImageFormat {
    /// Graphics Interchange Format image.
    Gif,
    /// Joint Photographic Experts Group image.
    Jpeg,
    /// Portable Network Graphics image.
    Png,
    /// Scalable Vector Graphics image.
    Svg,
    /// Tagged Image File Format image.
    Tiff,
    /// WebP image.
    Webp,
}

impl SupportedImageFormat {
    /// Returns whether the image format is supported for public previews and credentials.
    fn is_public_supported(&self) -> bool {
        matches!(self, Self::Jpeg | Self::Png | Self::Webp)
    }

    /// Returns the MIME type associated with the format.
    fn mime_type(&self) -> &'static str {
        match self {
            SupportedImageFormat::Gif => "image/gif",
            SupportedImageFormat::Jpeg => "image/jpeg",
            SupportedImageFormat::Png => "image/png",
            SupportedImageFormat::Svg => "image/svg+xml",
            SupportedImageFormat::Tiff => "image/tiff",
            SupportedImageFormat::Webp => "image/webp",
        }
    }
}

/// Metadata of an image that passed upload validation.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct ValidatedImage {
    /// MIME type determined for the image.
    pub content_type: &'static str,
    /// Lowercase file extension.
    pub extension: String,
}

// Helpers.

/// Detects the image format using the `image` crate with a fallback for SVGs.
fn detect_image_format(bytes: &[u8], extension: &str) -> Result<SupportedImageFormat> {
    match image::guess_format(bytes) {
        Ok(ImageFormat::Gif) => Ok(SupportedImageFormat::Gif),
        Ok(ImageFormat::Jpeg) => Ok(SupportedImageFormat::Jpeg),
        Ok(ImageFormat::Png) => Ok(SupportedImageFormat::Png),
        Ok(ImageFormat::Tiff) => Ok(SupportedImageFormat::Tiff),
        Ok(ImageFormat::WebP) => Ok(SupportedImageFormat::Webp),
        Ok(other) => Err(anyhow!("unsupported image format: {other:?}")),
        Err(_) if is_svg(bytes, extension) => Ok(SupportedImageFormat::Svg),
        Err(_) => Err(anyhow!("unsupported image format")),
    }
}

/// Returns the accepted extensions for the provided format.
fn expected_extensions(format: &SupportedImageFormat) -> &'static [&'static str] {
    match format {
        SupportedImageFormat::Gif => &["gif"],
        SupportedImageFormat::Jpeg => &["jpg", "jpeg"],
        SupportedImageFormat::Png => &["png"],
        SupportedImageFormat::Svg => &["svg"],
        SupportedImageFormat::Tiff => &["tif", "tiff"],
        SupportedImageFormat::Webp => &["webp"],
    }
}

/// Validates that the extension matches the detected image format.
fn extension_matches(format: &SupportedImageFormat, extension: &str) -> bool {
    expected_extensions(format)
        .iter()
        .any(|candidate| candidate == &extension)
}

/// Extracts the lowercase file extension from a file name.
fn image_extension(file_name: &str) -> Result<Cow<'_, str>> {
    let extension = file_name
        .rsplit('.')
        .next()
        .ok_or_else(|| anyhow!("missing file extension"))?;
    if extension.is_empty() {
        return Err(anyhow!("missing file extension"));
    }
    Ok(Cow::from(extension.to_ascii_lowercase()))
}

/// Checks whether an SVG href is safe to retain in an inline SVG document.
fn is_safe_svg_href(element_name: &[u8], value: &str) -> bool {
    // Normalize characters that can obscure an explicit URL scheme
    let normalized = value
        .chars()
        .filter(|character| !character.is_control() && !character.is_whitespace())
        .flat_map(char::to_lowercase)
        .collect::<String>();

    // Allow references without an explicit leading scheme
    let Some(colon_index) = normalized.find(':') else {
        return true;
    };
    let path_separator_index = normalized.find(['/', '?', '#']).unwrap_or(normalized.len());
    if colon_index > path_separator_index {
        return true;
    }

    // Restrict explicit schemes and inline image media types
    let (scheme, rest) = normalized.split_at(colon_index);
    match scheme {
        "http" | "https" => true,
        "data" if element_name.eq_ignore_ascii_case(b"image") => {
            let media_type = rest[1..]
                .split_once([';', ','])
                .map_or(rest[1..].as_ref(), |(media_type, _)| media_type);
            matches!(
                media_type,
                "image/gif" | "image/jpeg" | "image/jpg" | "image/png" | "image/webp"
            )
        }
        _ => false,
    }
}

/// Determines whether the provided bytes and extension represent a valid SVG asset.
///
/// This performs lightweight XML parsing to verify:
/// - The extension is "svg"
/// - The file is well-formed XML
/// - The root element is <svg> with proper namespace
/// - No dangerous elements (<script>, <foreignObject>)
/// - No event handler attributes (onclick, onload, etc.)
/// - No javascript: or suspicious data: URLs
fn is_svg(bytes: &[u8], extension: &str) -> bool {
    const SVG_NAMESPACE: &[u8] = b"http://www.w3.org/2000/svg";
    const DANGEROUS_ELEMENTS: &[&[u8]] = &[b"script", b"foreignObject"];

    // Check extension first (fast path)
    if !extension.eq_ignore_ascii_case("svg") {
        return false;
    }

    let mut reader = Reader::from_reader(bytes);
    reader.config_mut().trim_text(true);

    let mut buf = Vec::new();
    let mut found_svg_root = false;
    let mut in_root = false;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Eof) => break,
            Ok(Event::Start(ref e) | Event::Empty(ref e)) => {
                let tag_name = e.name();

                // Check for root <svg> element with proper namespace
                if !in_root {
                    if tag_name.as_ref() != b"svg" {
                        return false;
                    }

                    // Verify SVG namespace is present
                    let mut has_svg_namespace = false;
                    for attr in e.attributes() {
                        let Ok(attr) = attr else {
                            return false;
                        };
                        let Ok(value) = attr.decoded_and_normalized_value(
                            XmlVersion::Implicit1_0,
                            reader.decoder(),
                        ) else {
                            return false;
                        };

                        if attr.key.as_ref() == b"xmlns" && value.as_bytes() == SVG_NAMESPACE {
                            has_svg_namespace = true;
                        }
                    }

                    if !has_svg_namespace {
                        return false;
                    }

                    found_svg_root = true;
                    in_root = true;
                }

                // Check for dangerous elements
                for dangerous in DANGEROUS_ELEMENTS {
                    if tag_name.local_name().as_ref().eq_ignore_ascii_case(dangerous) {
                        return false;
                    }
                }

                // Check all attributes for dangerous content
                for attr in e.attributes() {
                    let Ok(attr) = attr else {
                        return false;
                    };
                    let key = attr.key.local_name();
                    let Ok(value) = attr
                        .decoded_and_normalized_value(XmlVersion::Implicit1_0, reader.decoder())
                    else {
                        return false;
                    };

                    // Block event handler attributes (onclick, onload, etc.)
                    if key.as_ref().len() >= 2 && key.as_ref()[..2].eq_ignore_ascii_case(b"on") {
                        return false;
                    }

                    // Restrict every namespace variant of href to safe URL forms
                    if key.as_ref().eq_ignore_ascii_case(b"href")
                        && !is_safe_svg_href(tag_name.local_name().as_ref(), &value)
                    {
                        return false;
                    }
                }
            }
            Ok(_) => {}
            Err(_) => return false,
        }
        buf.clear();
    }

    if !found_svg_root {
        return false;
    }

    true
}
