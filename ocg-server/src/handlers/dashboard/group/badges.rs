//! Group dashboard badge definition, artwork, award, and revocation handlers.

use std::{io::Cursor, path::Path as FilePath};

use anyhow::Result;
use askama::Template;
use axum::{
    Form, Json,
    extract::{Path, Query, RawQuery, State},
    http::{HeaderName, HeaderValue, StatusCode},
    response::{Html, IntoResponse},
};
use chrono::{NaiveDate, TimeDelta, Utc};
use garde::Validate;
use image::{GenericImageView, ImageFormat, ImageReader, Limits};
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId},
    },
    router::serde_qs_config,
    services::images::{DynImageStorage, Image},
    templates::dashboard::group::badges::{
        ArtworkPage, AwardsFilters, AwardsPage, BadgesFilters, BadgesPage,
    },
    types::{
        badges::{
            AwardedBadgesFilters, BADGE_CRITERIA_MAX_CHARS, BADGE_DESCRIPTION_MAX_CHARS,
            BADGE_NAME_MAX_CHARS, BadgeAwardInput, BadgeFilters, BadgeInput,
        },
        pagination::{self, NavigationLinks},
    },
};

#[cfg(test)]
mod tests;

/// Full dashboard URL for badge artwork.
const ARTWORK_DASHBOARD_URL: &str = "/dashboard/group?tab=artwork";

/// Full dashboard URL for badge awards.
const AWARDS_DASHBOARD_URL: &str = "/dashboard/group?tab=awards";

/// Partial dashboard URL for badge awards.
const AWARDS_PARTIAL_URL: &str = "/dashboard/group/awards";

/// Required badge artwork height and width.
const BADGE_ARTWORK_SIZE: u32 = 512;

/// Full dashboard URL for badge definitions.
const BADGES_DASHBOARD_URL: &str = "/dashboard/group?tab=badges";

/// Partial dashboard URL for badge definitions.
const BADGES_PARTIAL_URL: &str = "/dashboard/group/badges";

/// Maximum stored badge artwork size accepted by the upload boundary.
const MAX_BADGE_ARTWORK_SIZE_BYTES: usize = 1024 * 1024;

/// Largest badge-list offset accepted by database integer parameters.
const MAX_DATABASE_OFFSET: usize = i32::MAX as usize;

// Pages handlers.

/// Renders the badge artwork page.
#[instrument(skip_all, err)]
pub(crate) async fn artwork_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the artwork page through its shared preparation path
    let template = prepare_artwork_page(&db, group_id).await?;

    // Keep browser navigation on the full dashboard URL
    let headers = [(
        HeaderName::from_static("hx-push-url"),
        HeaderValue::from_static(ARTWORK_DASHBOARD_URL),
    )];

    Ok((headers, Html(template.render()?)))
}

/// Renders the badge award history page.
#[instrument(skip_all, err)]
pub(crate) async fn awards_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the awards page through its shared preparation path
    let (filters, template) =
        prepare_awards_page(&db, group_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Keep browser navigation on the full dashboard URL
    let url = pagination::build_url(AWARDS_DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Renders the badge definitions page.
#[instrument(skip_all, err)]
pub(crate) async fn badges_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Load the definitions page through its shared preparation path
    let (filters, template) =
        prepare_badges_page(&db, group_id, raw_query.as_deref().unwrap_or_default()).await?;

    // Keep browser navigation on the full dashboard URL
    let url = pagination::build_url(BADGES_DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Return searchable badge definitions for the shared award modal.
#[instrument(skip_all, err)]
pub(crate) async fn options(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Query(query): Query<OptionsQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Normalize search input before querying bounded modal options
    let query = query
        .query
        .map(|query| query.trim().to_string())
        .filter(|query| !query.is_empty());
    let badges = db
        .list_badges(
            group_id,
            &BadgeFilters {
                limit: 50,
                offset: 0,
                query,
            },
        )
        .await?;

    Ok(Json(badges))
}

// Actions handlers.

/// Create one group badge definition.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Form(input): Form<BadgeInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate route-safe inputs before the audited database mutation
    validate_badge_input(&input)?;
    db.add_badge(user.user_id, community_id, group_id, &input).await?;
    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Add an uploaded image to the reusable artwork gallery.
#[instrument(skip_all, err)]
pub(crate) async fn add_artwork(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(image_storage): State<DynImageStorage>,
    Form(input): Form<ArtworkInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate the stored basename and image before adding the gallery reference
    let file_name = input.file_name.trim();
    if !is_safe_artwork_file_name(file_name) {
        return Err(HandlerError::Deserialization(
            "artwork filename is invalid".to_string(),
        ));
    }
    let image = image_storage
        .get(file_name)
        .await?
        .ok_or_else(|| HandlerError::Deserialization("badge artwork was not found".to_string()))?;
    validate_badge_artwork(file_name, &image)?;
    db.add_badge_artwork(user.user_id, community_id, group_id, file_name)
        .await?;
    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Award one badge to an explicit recipient list.
#[instrument(skip_all, err)]
pub(crate) async fn award(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Json(input): Json<AwardInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject empty recipient sets before entering the audited database mutation
    if input.user_ids.is_empty() {
        return Err(HandlerError::Deserialization(
            "badge recipients cannot be empty".to_string(),
        ));
    }

    // Validate and durably queue the complete award set atomically
    let outcome = db
        .award_badge(
            user.user_id,
            community_id,
            group_id,
            &BadgeAwardInput {
                badge_id: input.badge_id,
                user_ids: input.user_ids,
                event_id: input.event_id,
            },
        )
        .await?;
    Ok((StatusCode::CREATED, Json(outcome)))
}

/// Delete one definition while retaining historical credential snapshots.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(badge_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete only the current definition while retaining issued snapshots
    db.delete_badge(user.user_id, community_id, group_id, badge_id)
        .await?;
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Remove an unreferenced image from the reusable artwork gallery.
#[instrument(skip_all, err)]
pub(crate) async fn delete_artwork(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(badge_artwork_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete only artwork that is no longer referenced
    db.delete_badge_artwork(user.user_id, community_id, group_id, badge_artwork_id)
        .await?;
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Resolve attendee badge recipients for one event-owned bypass option.
#[instrument(skip_all, err)]
pub(crate) async fn recipients(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(event_id): Path<Uuid>,
    Query(query): Query<RecipientsQuery>,
) -> Result<impl IntoResponse, HandlerError> {
    // Resolve the exact current attendee set before opening the generic modal
    let user_ids = db
        .list_event_attendees_ids(
            group_id,
            event_id,
            query.scope == RecipientScope::CheckedInAttendees,
        )
        .await?;

    Ok(Json(RecipientsOutput { user_ids }))
}

/// Permanently revoke one active group-issued credential with a private reason.
#[instrument(skip_all, err)]
pub(crate) async fn revoke(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_badge_id): Path<Uuid>,
    Form(input): Form<RevokeInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Permanently revoke the credential with its private audit reason
    db.revoke_group_user_badge(
        user.user_id,
        community_id,
        group_id,
        user_badge_id,
        &input.reason,
    )
    .await?;
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Update one group badge definition.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(badge_id): Path<Uuid>,
    Form(input): Form<BadgeInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate route-safe inputs before the audited database mutation
    validate_badge_input(&input)?;
    db.update_badge(user.user_id, community_id, group_id, badge_id, &input)
        .await?;
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

// Types.

/// Artwork gallery form fields.
#[derive(Debug, Deserialize)]
pub(crate) struct ArtworkInput {
    /// Content-addressed uploaded filename.
    file_name: String,
}

/// Constrained badge award request.
#[derive(Debug, Deserialize)]
pub(crate) struct AwardInput {
    /// Badge definition to award.
    badge_id: Uuid,
    /// Explicit recipients to validate and award atomically.
    user_ids: Vec<Uuid>,

    /// Event that defines recipient eligibility, when applicable.
    event_id: Option<Uuid>,
}

/// Search fields accepted by the shared award modal.
#[derive(Debug, Default, Deserialize)]
pub(crate) struct OptionsQuery {
    /// Badge definition search text.
    query: Option<String>,
}

/// Attendee bypass option query fields.
#[derive(Debug, Deserialize)]
pub(crate) struct RecipientsQuery {
    /// Attendee set to resolve.
    scope: RecipientScope,
}

/// Resolved attendee identifiers returned to the browser.
#[derive(Debug, serde::Serialize)]
pub(crate) struct RecipientsOutput {
    /// Explicit current recipient identifiers.
    user_ids: Vec<Uuid>,
}

/// Supported attendee bypass options.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum RecipientScope {
    /// All verified confirmed attendees.
    AllAttendees,
    /// Verified confirmed attendees who are checked in.
    CheckedInAttendees,
}

/// Permanent group revocation form fields.
#[derive(Debug, Deserialize)]
pub(crate) struct RevokeInput {
    /// Private internal revocation reason.
    reason: String,
}

// Helpers.

/// Prepares the badge artwork page for full and partial dashboard routes.
pub(crate) async fn prepare_artwork_page(
    db: &DynDB,
    group_id: Uuid,
) -> Result<ArtworkPage, HandlerError> {
    // Load the reusable artwork collection
    let artwork = db.list_badge_artwork(group_id).await?;

    Ok(ArtworkPage { artwork })
}

/// Prepares the badge award history page for full and partial dashboard routes.
pub(crate) async fn prepare_awards_page(
    db: &DynDB,
    group_id: Uuid,
    raw_query: &str,
) -> Result<(AwardsFilters, AwardsPage), HandlerError> {
    // Parse and validate the award-history filters
    let filters: AwardsFilters = serde_qs_config().deserialize_str(raw_query)?;
    filters.validate()?;
    let offset = filters.awards_offset.unwrap_or(0);
    if offset > MAX_DATABASE_OFFSET {
        return Err(HandlerError::Deserialization(
            "award history offset is too large".to_string(),
        ));
    }
    let limit = filters.limit.expect("validated pagination limit to be set");
    let from = filters.from.clone().unwrap_or_default();
    let query = filters.awards_query.clone().unwrap_or_default();
    let status = filters.status.clone().unwrap_or_default();
    let to = filters.to.clone().unwrap_or_default();
    let from_filter = parse_date_filter("from", &from)?;
    let to_filter = parse_to_date_filter(&to)?;
    let award_filters = AwardedBadgesFilters {
        limit,
        offset,
        badge_id: filters.badge_id,
        event_id: filters.event_id,
        from: from_filter,
        query: filters.awards_query.clone(),
        status: filters.status.clone(),
        to: to_filter,
    };

    // Load the filtered award history
    let awarded_badges = db.list_awarded_badges(group_id, &award_filters).await?;

    // Build navigation within the top-level awards tab
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        awarded_badges.total,
        AWARDS_DASHBOARD_URL,
        AWARDS_PARTIAL_URL,
    )?;

    // Assemble the award page with its current filters
    let template = AwardsPage {
        awarded_badges,
        from,
        navigation_links,
        query,
        status,
        to,

        badge_id: filters.badge_id,
        event_id: filters.event_id,
        limit: filters.limit,
        offset: filters.awards_offset,
    };

    Ok((filters, template))
}

/// Prepares the badge definitions page for full and partial dashboard routes.
pub(crate) async fn prepare_badges_page(
    db: &DynDB,
    group_id: Uuid,
    raw_query: &str,
) -> Result<(BadgesFilters, BadgesPage), HandlerError> {
    // Parse and validate the badge-definition filters
    let filters: BadgesFilters = serde_qs_config().deserialize_str(raw_query)?;
    filters.validate()?;
    let offset = filters.badges_offset.unwrap_or(0);
    if offset > MAX_DATABASE_OFFSET {
        return Err(HandlerError::Deserialization(
            "badge definition offset is too large".to_string(),
        ));
    }
    let limit = filters.limit.expect("validated pagination limit to be set");
    let query = filters.badges_query.clone().unwrap_or_default();
    let badge_filters = BadgeFilters {
        limit,
        offset,
        query: filters.badges_query.clone(),
    };

    // Load definitions and their reusable artwork concurrently
    let (artwork, badges) = tokio::try_join!(
        db.list_badge_artwork(group_id),
        db.list_badges(group_id, &badge_filters)
    )?;

    // Build navigation within the top-level badges tab
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        badges.total,
        BADGES_DASHBOARD_URL,
        BADGES_PARTIAL_URL,
    )?;

    // Assemble the definitions page with its current filters
    let template = BadgesPage {
        artwork,
        badges,
        navigation_links,
        query,

        limit: filters.limit,
        offset: filters.badges_offset,
    };

    Ok((filters, template))
}

/// Return whether a stored image name is a bounded, route-safe basename.
fn is_safe_artwork_file_name(file_name: &str) -> bool {
    let mut bytes = file_name.bytes();
    (1..=80).contains(&file_name.len())
        && bytes.next().is_some_and(|byte| byte.is_ascii_alphanumeric())
        && bytes.all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

/// Parse a date-only award filter at UTC midnight.
fn parse_date_filter(
    field_name: &str,
    value: &str,
) -> Result<Option<chrono::DateTime<Utc>>, HandlerError> {
    if value.is_empty() {
        return Ok(None);
    }

    let date = NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| HandlerError::Deserialization(format!("{field_name} date is invalid")))?;
    let date = date
        .and_hms_opt(0, 0, 0)
        .ok_or_else(|| HandlerError::Deserialization(format!("{field_name} date is invalid")))?;
    Ok(Some(date.and_utc()))
}

/// Parse the inclusive latest award date into an exclusive upper bound.
fn parse_to_date_filter(value: &str) -> Result<Option<chrono::DateTime<Utc>>, HandlerError> {
    parse_date_filter("to", value)?
        .map(|date| {
            date.checked_add_signed(TimeDelta::days(1))
                .ok_or_else(|| HandlerError::Deserialization("to date is invalid".to_string()))
        })
        .transpose()
}

/// Require a bounded 512×512 PNG, JPEG, or WebP stored image.
fn validate_badge_artwork(file_name: &str, image: &Image) -> Result<(), HandlerError> {
    let invalid = || {
        HandlerError::Deserialization(
            "badge artwork must be a 512x512 PNG, JPEG, or WebP image".to_string(),
        )
    };
    if image.bytes.len() > MAX_BADGE_ARTWORK_SIZE_BYTES {
        return Err(invalid());
    }

    let mut reader = ImageReader::new(Cursor::new(&image.bytes))
        .with_guessed_format()
        .map_err(|_| invalid())?;
    let extension = FilePath::new(file_name)
        .extension()
        .and_then(|extension| extension.to_str());
    let format_matches = match reader.format() {
        Some(ImageFormat::Jpeg) => {
            extension.is_some_and(|extension| {
                extension.eq_ignore_ascii_case("jpeg") || extension.eq_ignore_ascii_case("jpg")
            }) && image.content_type == "image/jpeg"
        }
        Some(ImageFormat::Png) => {
            extension.is_some_and(|extension| extension.eq_ignore_ascii_case("png"))
                && image.content_type == "image/png"
        }
        Some(ImageFormat::WebP) => {
            extension.is_some_and(|extension| extension.eq_ignore_ascii_case("webp"))
                && image.content_type == "image/webp"
        }
        _ => false,
    };
    if !format_matches {
        return Err(invalid());
    }

    let mut limits = Limits::default();
    limits.max_alloc = Some(16 * 1024 * 1024);
    limits.max_image_height = Some(BADGE_ARTWORK_SIZE);
    limits.max_image_width = Some(BADGE_ARTWORK_SIZE);
    reader.limits(limits);
    let decoded = reader.decode().map_err(|_| invalid())?;
    if decoded.dimensions() != (BADGE_ARTWORK_SIZE, BADGE_ARTWORK_SIZE) {
        return Err(invalid());
    }
    Ok(())
}

/// Enforce required badge definition fields before calling the database.
fn validate_badge_input(input: &BadgeInput) -> Result<(), HandlerError> {
    let required_fields = [
        input.criteria.as_str(),
        input.description.as_str(),
        input.image_file_name.as_str(),
        input.name.as_str(),
    ];
    if required_fields.iter().any(|value| value.trim().is_empty())
        || !is_safe_artwork_file_name(input.image_file_name.trim())
    {
        return Err(HandlerError::Deserialization(
            "all badge fields are required".to_string(),
        ));
    }
    if input.criteria.chars().count() > BADGE_CRITERIA_MAX_CHARS
        || input.description.chars().count() > BADGE_DESCRIPTION_MAX_CHARS
        || input.name.chars().count() > BADGE_NAME_MAX_CHARS
    {
        return Err(HandlerError::Deserialization(
            "badge text exceeds the allowed length".to_string(),
        ));
    }
    Ok(())
}
