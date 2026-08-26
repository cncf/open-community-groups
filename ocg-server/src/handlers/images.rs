//! Handlers for uploading and serving image assets.

use std::{borrow::Cow, io::Cursor, str::FromStr};

use anyhow::{Context, Result, anyhow};
use axum::{
    Json,
    body::Body,
    extract::{Multipart, Path, State},
    http::{
        HeaderMap, HeaderName, HeaderValue, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    },
    response::IntoResponse,
};
use image::{ImageFormat, ImageReader};
use quick_xml::{Reader, XmlVersion, events::Event};
use serde_json::json;
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser, request_headers_match_site_origin},
    services::images::{
        DynImageStorage, NewImage, OPEN_GRAPH_IMAGE_HEIGHT, OPEN_GRAPH_IMAGE_WIDTH,
    },
    util::compute_hash,
};

#[cfg(test)]
mod tests;

/// Maximum payload size allowed for image uploads (1 MiB).
const MAX_IMAGE_SIZE_BYTES: usize = 1024 * 1024;

/// Cache-Control header for long-lived responses.
const CACHE_CONTROL_IMMUTABLE: &str = "public, max-age=31536000, immutable";

/// Content-Security-Policy header name.
const CONTENT_SECURITY_POLICY: HeaderName = HeaderName::from_static("content-security-policy");

/// Cross-Origin-Resource-Policy header name.
const CROSS_ORIGIN_RESOURCE_POLICY: HeaderName =
    HeaderName::from_static("cross-origin-resource-policy");

/// Cross-origin resource policy for publicly embeddable images.
const RESOURCE_POLICY_CROSS_ORIGIN: &str = "cross-origin";

/// Same-origin resource policy for images protected from hotlinking.
const RESOURCE_POLICY_SAME_ORIGIN: &str = "same-origin";

/// X-Content-Type-Options header name.
const X_CONTENT_TYPE_OPTIONS: HeaderName = HeaderName::from_static("x-content-type-options");

// Handlers

/// Serves previously uploaded images.
#[instrument(skip_all, err)]
pub(crate) async fn serve(
    headers: HeaderMap,
    State(image_storage): State<DynImageStorage>,
    State(server_cfg): State<HttpServerConfig>,
    Path(file_name): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Enforce same-origin loading unless public hotlinking is configured
    let resource_policy = if server_cfg.allow_image_hotlinking {
        RESOURCE_POLICY_CROSS_ORIGIN
    } else if request_headers_match_site_origin(&server_cfg, &headers)? {
        RESOURCE_POLICY_SAME_ORIGIN
    } else {
        return Ok(StatusCode::FORBIDDEN.into_response());
    };

    Ok(serve_image(&image_storage, &file_name, resource_policy)
        .await?
        .into_response())
}

/// Serves images referenced by current or historical badge credentials.
#[instrument(skip_all, err)]
pub(crate) async fn serve_badge(
    State(db): State<DynDB>,
    State(image_storage): State<DynImageStorage>,
    Path(file_name): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Keep historical credential artwork available while referenced
    if !db.is_badge_image(&file_name).await? {
        return Ok(StatusCode::NOT_FOUND.into_response());
    }

    Ok(
        serve_image(&image_storage, &file_name, RESOURCE_POLICY_CROSS_ORIGIN)
            .await?
            .into_response(),
    )
}

/// Serves images that are currently configured for public Open Graph previews.
#[instrument(skip_all, err)]
pub(crate) async fn serve_open_graph(
    State(db): State<DynDB>,
    State(image_storage): State<DynImageStorage>,
    Path(file_name): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Confirm the image is currently configured for public preview use
    if !db.is_open_graph_image(&file_name).await? {
        return Ok(StatusCode::NOT_FOUND.into_response());
    }

    Ok(
        serve_image(&image_storage, &file_name, RESOURCE_POLICY_CROSS_ORIGIN)
            .await?
            .into_response(),
    )
}

/// Handles authenticated image uploads.
#[instrument(skip_all, err)]
pub(crate) async fn upload(
    CurrentUser(user): CurrentUser,
    State(image_storage): State<DynImageStorage>,
    State(server_cfg): State<HttpServerConfig>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate the request against the configured site origin
    if !request_headers_match_site_origin(&server_cfg, &headers)? {
        return Ok((StatusCode::FORBIDDEN).into_response());
    }

    // Extract optional target, file name and bytes from multipart payload
    let mut target: Option<ImageTarget> = None;
    let mut file_name: Option<String> = None;
    let mut data: Option<bytes::Bytes> = None;

    while let Ok(Some(field)) = multipart.next_field().await {
        let field_name = field.name().map(str::to_string);

        match field_name.as_deref() {
            Some("target") => {
                let target_value = field.text().await.context("error reading target field")?;
                target = Some(ImageTarget::from_str(&target_value)?);
            }
            Some("file") => {
                file_name = field.file_name().map(str::to_string);
                data = Some(field.bytes().await.context("error reading uploaded image")?);
            }
            _ => {}
        }
    }

    // Ensure we have a file
    let Some(file_name) = file_name else {
        return Ok((StatusCode::BAD_REQUEST, "missing file in upload payload").into_response());
    };
    let Some(data) = data else {
        return Ok((StatusCode::BAD_REQUEST, "missing file in upload payload").into_response());
    };

    // Enforce maximum file size
    if data.len() > MAX_IMAGE_SIZE_BYTES {
        return Ok((StatusCode::PAYLOAD_TOO_LARGE, "image exceeds 1MB limit").into_response());
    }

    // Detect image format and check extension matches
    let extension = image_extension(&file_name)?;
    let format = detect_image_format(data.as_ref(), extension.as_ref())?;
    if !extension_matches(&format, extension.as_ref()) {
        return Ok((
            StatusCode::UNPROCESSABLE_ENTITY,
            "file extension does not match detected image format",
        )
            .into_response());
    }

    // Validate target-specific image requirements
    if let Some(target) = target {
        // Validate public credential and Open Graph image formats
        if matches!(target, ImageTarget::Badge | ImageTarget::OpenGraph)
            && !format.is_public_supported()
        {
            let target_name = if matches!(target, ImageTarget::Badge) {
                "Badge"
            } else {
                "Open Graph"
            };
            return Ok((
                StatusCode::UNPROCESSABLE_ENTITY,
                format!("{target_name} images must be PNG, JPEG, or WebP"),
            )
                .into_response());
        }

        // Validate target dimensions when the format supports dimension checks
        if !matches!(format, SupportedImageFormat::Svg)
            && let Err(e) = validate_image_dimensions(data.as_ref(), target)
        {
            return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response());
        }
    }

    // Compute file hash
    let hash = compute_hash(data.as_ref());

    // Store image using the configured storage provider
    let new_image = NewImage {
        bytes: data.as_ref(),
        content_type: mime_type(&format),
        file_name: &format!("{hash}.{extension}"),
        user_id: user.user_id,
    };
    image_storage.save(&new_image).await?;

    // Prepare response with image URL
    let image_path = if matches!(target, Some(ImageTarget::Badge)) {
        format!("/images/badges/{}", new_image.file_name)
    } else {
        format!("/images/{}", new_image.file_name)
    };
    let body = Json(json!({ "url": image_path }));

    Ok((StatusCode::CREATED, body).into_response())
}

// Helpers

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

/// Returns the MIME type associated with the provided format.
fn mime_type(format: &SupportedImageFormat) -> &'static str {
    match format {
        SupportedImageFormat::Gif => "image/gif",
        SupportedImageFormat::Jpeg => "image/jpeg",
        SupportedImageFormat::Png => "image/png",
        SupportedImageFormat::Svg => "image/svg+xml",
        SupportedImageFormat::Tiff => "image/tiff",
        SupportedImageFormat::Webp => "image/webp",
    }
}

/// Loads an image from storage and returns an immutable public response.
async fn serve_image(
    image_storage: &DynImageStorage,
    file_name: &str,
    resource_policy: &'static str,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the image bytes and content type from storage
    let Some(image) = image_storage.get(file_name).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    // Prepare immutable cache and content headers
    let mut response_headers = HeaderMap::new();
    response_headers.insert(
        CACHE_CONTROL,
        HeaderValue::from_static(CACHE_CONTROL_IMMUTABLE),
    );
    response_headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_str(&image.content_type)
            .map_err(|err| HandlerError::Other(err.into()))?,
    );
    response_headers.insert(
        CROSS_ORIGIN_RESOURCE_POLICY,
        HeaderValue::from_static(resource_policy),
    );
    response_headers.insert(X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    if image.content_type == "image/svg+xml" {
        response_headers.insert(CONTENT_SECURITY_POLICY, HeaderValue::from_static("sandbox"));
    }

    // Build the image response body
    let body = Body::from(image.bytes);

    Ok((StatusCode::OK, response_headers, body).into_response())
}

/// Validates image dimensions match the target requirements.
fn validate_image_dimensions(bytes: &[u8], target: ImageTarget) -> Result<()> {
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

// Types

/// Image target defining expected dimensions.
#[derive(Clone, Copy)]
enum ImageTarget {
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
    fn dimensions(self) -> (u32, u32) {
        match self {
            ImageTarget::Badge => (512, 512),
            ImageTarget::Banner => (2428, 192),
            ImageTarget::BannerMobile => (1220, 192),
            ImageTarget::Logo => (360, 360),
            ImageTarget::OpenGraph => (OPEN_GRAPH_IMAGE_WIDTH, OPEN_GRAPH_IMAGE_HEIGHT),
        }
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

/// Supported image formats accepted by the upload endpoint.
enum SupportedImageFormat {
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
}
