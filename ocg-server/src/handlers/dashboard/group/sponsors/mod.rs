//! HTTP handlers for managing sponsors in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedCommunityId, SelectedGroupId, ValidatedForm},
    },
    router::serde_qs_config,
    templates::dashboard::group::sponsors::{self, GroupSponsorsFilters, Sponsor},
    types::{
        pagination::{self, NavigationLinks},
        permissions::GroupPermission,
    },
};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Displays the page to add a new sponsor.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let can_manage_sponsors = db
        .user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::SponsorsWrite,
        )
        .await?;
    let template = sponsors::AddPage {
        can_manage_sponsors,
        group_id,
    };

    Ok(Html(template.render()?))
}

/// Displays the list of sponsors for the group dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    // Fetch sponsors
    let filters: GroupSponsorsFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let (can_manage_sponsors, results) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::SponsorsWrite
        ),
        db.list_group_sponsors(group_id, &filters, false)
    )?;

    // Prepare template
    let navigation_links = NavigationLinks::from_filters(
        &filters,
        results.total,
        "/dashboard/group?tab=sponsors",
        "/dashboard/group/sponsors",
    )?;
    let template = sponsors::ListPage {
        can_manage_sponsors,
        navigation_links,
        sponsors: results.sponsors,
        total: results.total,
        limit: filters.limit,
        offset: filters.offset,
    };

    // Prepare response headers
    let url = pagination::build_url("/dashboard/group?tab=sponsors", &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Displays the page to update an existing sponsor.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    CurrentUser(user): CurrentUser,
    SelectedCommunityId(community_id): SelectedCommunityId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(group_sponsor_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (can_manage_sponsors, sponsor) = tokio::try_join!(
        db.user_has_group_permission(
            &community_id,
            &group_id,
            &user.user_id,
            GroupPermission::SponsorsWrite
        ),
        db.get_group_sponsor(group_id, group_sponsor_id)
    )?;
    let template = sponsors::UpdatePage {
        can_manage_sponsors,
        group_id,
        sponsor,
    };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a new sponsor to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(sponsor): ValidatedForm<Sponsor>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add sponsor to database
    db.add_group_sponsor(group_id, &sponsor).await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
        .into_response())
}

/// Deletes a sponsor from the database.
#[instrument(skip_all, err)]
pub(crate) async fn delete(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(group_sponsor_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Delete the sponsor from database
    db.delete_group_sponsor(group_id, group_sponsor_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}

/// Updates an existing sponsor in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(group_sponsor_id): Path<Uuid>,
    ValidatedForm(sponsor): ValidatedForm<Sponsor>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update sponsor in database
    db.update_group_sponsor(group_id, group_sponsor_id, &sponsor).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    ))
}
