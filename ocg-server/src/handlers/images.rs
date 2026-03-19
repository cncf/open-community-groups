//! Handlers for uploading and serving image assets.

use std::{borrow::Cow, io::Cursor, str::FromStr};

use anyhow::{Context, Result, anyhow};
use axum::{
    Json,
    body::Body,
    extract::{Multipart, Path, State},
    http::{
        HeaderMap, HeaderValue, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    },
    response::IntoResponse,
};
use image::{ImageFormat, ImageReader};
use quick_xml::{Reader, events::Event};
use serde_json::json;
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    handlers::{error::HandlerError, extractors::CurrentUser, request_matches_site},
    services::images::{DynImageStorage, NewImage},
    util::compute_hash,
};

#[cfg(test)]
mod tests;

/// Maximum payload size allowed for image uploads (1 MiB).
const MAX_IMAGE_SIZE_BYTES: usize = 1024 * 1024;

/// Cache-Control header for long-lived responses.
const CACHE_CONTROL_IMMUTABLE: &str = "public, max-age=31536000, immutable";

// Handlers

/// Serves previously uploaded images.
#[instrument(skip_all, err)]
pub(crate) async fn serve(
    headers: HeaderMap,
    State(image_storage): State<DynImageStorage>,
    State(server_cfg): State<HttpServerConfig>,
    Path(file_name): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate referer header matches configured hostname.
    if !request_matches_site(&server_cfg, &headers)? {
        return Ok(StatusCode::FORBIDDEN.into_response());
    }

    // Retrieve image from storage
    let Some(image) = image_storage.get(&file_name).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    // Prepare headers and body
    let mut response_headers = HeaderMap::new();
    response_headers.insert(CACHE_CONTROL, HeaderValue::from_static(CACHE_CONTROL_IMMUTABLE));
    response_headers.insert(
        CONTENT_TYPE,
        HeaderValue::from_str(&image.content_type).map_err(|err| HandlerError::Other(err.into()))?,
    );
    let body = Body::from(image.bytes);

    Ok((StatusCode::OK, response_headers, body).into_response())
}

/// Handles authenticated image uploads.
#[instrument(skip_all, err)]
pub(crate) async fn upload(
    CurrentUser(user): CurrentUser,
    State(server_cfg): State<HttpServerConfig>,
    State(image_storage): State<DynImageStorage>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate referer header matches configured hostname
    if !request_matches_site(&server_cfg, &headers)? {
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

    // Validate dimensions if target is specified and image is not SVG
    if let Some(target) = target
        && !matches!(format, SupportedImageFormat::Svg)
        && let Err(e) = validate_image_dimensions(data.as_ref(), target)
    {
        return Ok((StatusCode::UNPROCESSABLE_ENTITY, e.to_string()).into_response());
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
    let body = Json(json!({ "url": format!("/images/{}", new_image.file_name) }));

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
                    let has_svg_namespace = e.attributes().filter_map(Result::ok).any(|attr| {
                        (attr.key.as_ref() == b"xmlns" || attr.key.local_name().as_ref() == b"xmlns")
                            && attr.value.as_ref() == SVG_NAMESPACE
                    });

                    if !has_svg_namespace {
                        return false;
                    }

                    found_svg_root = true;
                    in_root = true;
                }

                // Check for dangerous elements
                for dangerous in DANGEROUS_ELEMENTS {
                    if tag_name.as_ref().eq_ignore_ascii_case(dangerous) {
                        return false;
                    }
                }

                // Check all attributes for dangerous content
                for attr in e.attributes().filter_map(Result::ok) {
                    let key = attr.key.as_ref();
                    let value = attr.value.as_ref();

                    // Block event handler attributes (onclick, onload, etc.)
                    if key.len() >= 2 && key[..2].eq_ignore_ascii_case(b"on") {
                        return false;
                    }

                    // Block javascript: URLs
                    if (key == b"href" || key == b"xlink:href")
                        && value.len() >= 11
                        && value[..11].eq_ignore_ascii_case(b"javascript:")
                    {
                        return false;
                    }

                    // Block suspicious data: URLs that might contain scripts
                    if (key == b"href" || key == b"xlink:href")
                        && value.len() >= 5
                        && value[..5].eq_ignore_ascii_case(b"data:")
                    {
                        // Allow data:image/ but block other data: URLs
                        if value.len() < 11 || !value[5..11].eq_ignore_ascii_case(b"image/") {
                            return false;
                        }
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
    Banner,
    BannerMobile,
    Logo,
}

impl ImageTarget {
    /// Returns (width, height) for the target.
    fn dimensions(self) -> (u32, u32) {
        match self {
            ImageTarget::Banner => (2428, 192),
            ImageTarget::BannerMobile => (1220, 192),
            ImageTarget::Logo => (360, 360),
        }
    }
}

impl FromStr for ImageTarget {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self> {
        match s {
            "banner" => Ok(ImageTarget::Banner),
            "banner_mobile" => Ok(ImageTarget::BannerMobile),
            "logo" => Ok(ImageTarget::Logo),
            _ => Err(anyhow!("unknown image target: {s}")),
        }
    }
}

/// Supported image formats accepted by the upload endpoint.
enum SupportedImageFormat {
    Gif,
    Jpeg,
    Png,
    Svg,
    Tiff,
    Webp,
}
