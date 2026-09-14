//! Handlers for uploading and serving image assets.

use std::str::FromStr;

use anyhow::{Context, Result};
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
use serde_json::json;
use tracing::instrument;

use crate::{
    config::HttpServerConfig,
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser, request_headers_match_site_origin},
    services::images::{
        DynImageStorage, NewImage,
        validation::{ImageTarget, ImageValidationError, validate_image_upload},
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

    // Validate the format, extension, and target requirements
    let validated = match validate_image_upload(&file_name, data.as_ref(), target) {
        Ok(validated) => validated,
        Err(ImageValidationError::Unsupported(err)) => return Err(HandlerError::from(err)),
        Err(err) => {
            return Ok((StatusCode::UNPROCESSABLE_ENTITY, err.to_string()).into_response());
        }
    };

    // Compute file hash
    let hash = compute_hash(data.as_ref());

    // Store image using the configured storage provider
    let new_image = NewImage {
        bytes: data.as_ref(),
        content_type: validated.content_type,
        file_name: &format!("{hash}.{}", validated.extension),
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
