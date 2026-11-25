//! Group dashboard badge definition, artwork, award, and revocation handlers.

use anyhow::Result;
use askama::Template;
use axum::{
    Json,
    extract::{Path, Query, RawQuery, State},
    http::{HeaderName, HeaderValue, StatusCode},
    response::{Html, IntoResponse},
};
use chrono::{NaiveDate, TimeDelta, Utc};
use garde::Validate;
use serde::Deserialize;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{
            CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm, ValidatedQuery,
        },
    },
    services::images::DynImagesManager,
    templates::dashboard::group::badges::{ArtworkPage, AwardsPage, BadgesPage},
    types::{
        badges::{
            AwardedBadgesFilters, BADGE_REVOCATION_REASON_MAX_CHARS, BadgeAwardInput, BadgeFilters,
            BadgeInput,
        },
        dashboard::group::badges::{AwardsFilters, BadgesFilters},
        pagination::{self, NavigationLinks},
    },
    validation::{trimmed_non_empty, valid_artwork_file_name},
};

#[cfg(test)]
mod tests;

/// Full dashboard URL for badge artwork.
const ARTWORK_DASHBOARD_URL: &str = "/dashboard/group?tab=artwork";

/// Full dashboard URL for badge awards.
const AWARDS_DASHBOARD_URL: &str = "/dashboard/group?tab=awards";

/// Partial dashboard URL for badge awards.
const AWARDS_PARTIAL_URL: &str = "/dashboard/group/awards";

/// Full dashboard URL for badge definitions.
const BADGES_DASHBOARD_URL: &str = "/dashboard/group?tab=badges";

/// Partial dashboard URL for badge definitions.
const BADGES_PARTIAL_URL: &str = "/dashboard/group/badges";

/// Largest badge-list offset accepted by database integer parameters.
const MAX_DATABASE_OFFSET: usize = i32::MAX as usize;

// Pages handlers.

/// Renders the badge artwork page.
#[instrument(skip_all)]
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
#[instrument(skip_all)]
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
#[instrument(skip_all)]
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

// JSON handlers.

/// Return searchable badge definitions for the shared award modal.
#[instrument(skip_all)]
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
#[instrument(skip_all)]
pub(crate) async fn add(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<BadgeInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Create the badge definition
    db.add_badge(user.user_id, community_id, group_id, &input).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Add an uploaded image to the reusable artwork gallery.
#[instrument(skip_all)]
pub(crate) async fn add_artwork(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    State(images_manager): State<DynImagesManager>,
    ValidatedForm(input): ValidatedForm<ArtworkInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Validate the stored image before adding the gallery reference
    let file_name = input.file_name.trim();
    images_manager.validate_badge_artwork(file_name).await?;

    // Register the artwork in the group's gallery
    db.add_badge_artwork(user.user_id, community_id, group_id, file_name)
        .await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Award one badge to an explicit recipient list.
#[instrument(skip_all)]
pub(crate) async fn award(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Json(input): Json<AwardInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Reject empty recipient sets before entering the audited database mutation
    if input.user_ids.is_empty() {
        return Err(HandlerError::Rejected(
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
#[instrument(skip_all)]
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
#[instrument(skip_all)]
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
#[instrument(skip_all)]
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
#[instrument(skip_all)]
pub(crate) async fn revoke(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(user_badge_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<RevokeInput>,
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
#[instrument(skip_all)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(badge_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<BadgeInput>,
) -> Result<impl IntoResponse, HandlerError> {
    // Persist the validated badge definition update
    db.update_badge(user.user_id, community_id, group_id, badge_id, &input)
        .await?;
    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

// Types.

/// Artwork gallery form fields.
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct ArtworkInput {
    /// Content-addressed uploaded filename.
    #[garde(custom(valid_artwork_file_name))]
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
#[derive(Debug, Deserialize, Validate)]
pub(crate) struct RevokeInput {
    /// Private internal revocation reason.
    #[garde(custom(trimmed_non_empty), custom(valid_revocation_reason_length))]
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
    let filters: AwardsFilters = ValidatedQuery::parse(raw_query)?;
    let offset = filters.awards_offset.unwrap_or(0);
    if offset > MAX_DATABASE_OFFSET {
        return Err(HandlerError::Rejected(
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
        from: from_filter,
        query: filters.awards_query.clone(),
        source: filters.source,
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
        limit: filters.limit,
        offset: filters.awards_offset,
        source: filters.source,
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
    let filters: BadgesFilters = ValidatedQuery::parse(raw_query)?;
    let offset = filters.badges_offset.unwrap_or(0);
    if offset > MAX_DATABASE_OFFSET {
        return Err(HandlerError::Rejected(
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

/// Parse a date-only award filter at UTC midnight.
fn parse_date_filter(
    field_name: &str,
    value: &str,
) -> Result<Option<chrono::DateTime<Utc>>, HandlerError> {
    if value.is_empty() {
        return Ok(None);
    }

    let date = NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| HandlerError::Rejected(format!("{field_name} date is invalid")))?;
    let date = date
        .and_hms_opt(0, 0, 0)
        .ok_or_else(|| HandlerError::Rejected(format!("{field_name} date is invalid")))?;
    Ok(Some(date.and_utc()))
}

/// Parse the inclusive latest award date into an exclusive upper bound.
fn parse_to_date_filter(value: &str) -> Result<Option<chrono::DateTime<Utc>>, HandlerError> {
    parse_date_filter("to", value)?
        .map(|date| {
            date.checked_add_signed(TimeDelta::days(1))
                .ok_or_else(|| HandlerError::Rejected("to date is invalid".to_string()))
        })
        .transpose()
}

/// Validates that a revocation reason stays within the form character limit
/// after normalizing browser CRLF line endings to LF.
#[allow(clippy::trivially_copy_pass_by_ref)]
fn valid_revocation_reason_length(value: &impl AsRef<str>, _ctx: &()) -> garde::Result {
    let len = value.as_ref().replace("\r\n", "\n").chars().count();
    if len > BADGE_REVOCATION_REASON_MAX_CHARS {
        return Err(garde::Error::new(format!(
            "length is greater than {BADGE_REVOCATION_REASON_MAX_CHARS}"
        )));
    }
    Ok(())
}
