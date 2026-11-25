//! Handlers for uploading and serving image assets.

use std::str::FromStr;

use anyhow::Result;
use axum::{
    Json,
    body::Body,
    extract::{
        Multipart, Path, State,
        multipart::{Field, MultipartError},
    },
    http::{
        HeaderMap, HeaderName, HeaderValue, StatusCode,
        header::{CACHE_CONTROL, CONTENT_TYPE},
    },
    response::IntoResponse,
};
use serde_json::json;
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser, request_headers_match_site_origin},
    services::images::{DynImagesManager, MAX_IMAGE_SIZE_BYTES, UploadImageInput},
    types::images::ImageTarget,
};

#[cfg(test)]
mod tests;

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
#[instrument(skip_all)]
pub(crate) async fn serve(
    headers: HeaderMap,
    State(images_manager): State<DynImagesManager>,
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

    Ok(serve_image(&images_manager, &file_name, resource_policy)
        .await?
        .into_response())
}

/// Serves images referenced by current or historical badge credentials.
#[instrument(skip_all)]
pub(crate) async fn serve_badge(
    State(db): State<DynDB>,
    State(images_manager): State<DynImagesManager>,
    Path(file_name): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Keep historical credential artwork available while referenced
    if !db.is_badge_image(&file_name).await? {
        return Ok(StatusCode::NOT_FOUND.into_response());
    }

    Ok(
        serve_image(&images_manager, &file_name, RESOURCE_POLICY_CROSS_ORIGIN)
            .await?
            .into_response(),
    )
}

/// Serves images that are currently configured for public Open Graph previews.
#[instrument(skip_all)]
pub(crate) async fn serve_open_graph(
    State(db): State<DynDB>,
    State(images_manager): State<DynImagesManager>,
    Path(file_name): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    // Confirm the image is currently configured for public preview use
    if !db.is_open_graph_image(&file_name).await? {
        return Ok(StatusCode::NOT_FOUND.into_response());
    }

    Ok(
        serve_image(&images_manager, &file_name, RESOURCE_POLICY_CROSS_ORIGIN)
            .await?
            .into_response(),
    )
}

/// Handles authenticated image uploads.
#[instrument(skip_all)]
pub(crate) async fn upload(
    CurrentUser(user): CurrentUser,
    State(images_manager): State<DynImagesManager>,
    State(server_cfg): State<HttpServerConfig>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate the request against the configured site origin
    if !request_headers_match_site_origin(&server_cfg, &headers)? {
        return Ok((StatusCode::FORBIDDEN).into_response());
    }

    // Stream optional target, file name, and bounded bytes from the multipart payload
    let mut target: Option<ImageTarget> = None;
    let mut file_name: Option<String> = None;
    let mut data: Option<Vec<u8>> = None;

    while let Some(field) = multipart.next_field().await? {
        let field_name = field.name().map(str::to_string);

        match field_name.as_deref() {
            Some("target") => {
                let target_value = field.text().await?;
                let Ok(parsed_target) = ImageTarget::from_str(&target_value) else {
                    return Ok((StatusCode::BAD_REQUEST, "unknown image target").into_response());
                };
                target = Some(parsed_target);
            }
            Some("file") => {
                file_name = field.file_name().map(str::to_string);
                let Some(bytes) = read_bounded_field(field, MAX_IMAGE_SIZE_BYTES).await? else {
                    return Ok(
                        (StatusCode::PAYLOAD_TOO_LARGE, "image exceeds 1MB limit").into_response()
                    );
                };
                data = Some(bytes);
            }
            _ => {}
        }
    }

    // Ensure we have a file
    let Some(file_name) = file_name else {
        return Ok((StatusCode::BAD_REQUEST, "missing file in upload payload").into_response());
    };
    let Some(bytes) = data else {
        return Ok((StatusCode::BAD_REQUEST, "missing file in upload payload").into_response());
    };

    // Delegate validation, hashing, and persistence to the images manager
    let stored_file_name = images_manager
        .upload(UploadImageInput {
            bytes,
            file_name,
            user_id: user.user_id,

            target,
        })
        .await?;

    // Prepare response with image URL
    let image_path = if matches!(target, Some(ImageTarget::Badge)) {
        format!("/images/badges/{stored_file_name}")
    } else {
        format!("/images/{stored_file_name}")
    };
    let body = Json(json!({ "url": image_path }));

    Ok((StatusCode::CREATED, body).into_response())
}

// Helpers

/// Reads a multipart field chunk by chunk, aborting once its size exceeds `max_bytes`.
async fn read_bounded_field(
    mut field: Field<'_>,
    max_bytes: usize,
) -> Result<Option<Vec<u8>>, MultipartError> {
    let mut buffer = Vec::new();
    while let Some(chunk) = field.chunk().await? {
        // Stop draining the stream as soon as the field crosses the byte limit
        if buffer.len().saturating_add(chunk.len()) > max_bytes {
            return Ok(None);
        }
        buffer.extend_from_slice(&chunk);
    }

    Ok(Some(buffer))
}

/// Loads an image through the manager and returns an immutable public response.
async fn serve_image(
    images_manager: &DynImagesManager,
    file_name: &str,
    resource_policy: &'static str,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the image bytes and content type through the images manager
    let Some(image) = images_manager.get(file_name).await? else {
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
