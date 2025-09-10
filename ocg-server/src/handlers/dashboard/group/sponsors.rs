//! HTTP handlers for managing sponsors in the group dashboard.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::{Form, Path, State},
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::SelectedGroupId},
    templates::dashboard::group::sponsors::{self, Sponsor},
};

// Pages handlers.

/// Displays the page to add a new sponsor.
#[instrument(skip_all, err)]
pub(crate) async fn add_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(_db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let template = sponsors::AddPage { group_id };

    Ok(Html(template.render()?))
}

/// Displays the list of sponsors for the group dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let sponsors = db.list_group_sponsors(group_id).await?;
    let template = sponsors::ListPage { sponsors };

    Ok(Html(template.render()?))
}

/// Displays the page to update an existing sponsor.
#[instrument(skip_all, err)]
pub(crate) async fn update_page(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(group_sponsor_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let sponsor = db.get_group_sponsor(group_id, group_sponsor_id).await?;
    let template = sponsors::UpdatePage { group_id, sponsor };

    Ok(Html(template.render()?))
}

// Actions handlers.

/// Adds a new sponsor to the database.
#[instrument(skip_all, err)]
pub(crate) async fn add(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Form(sponsor): Form<Sponsor>,
) -> Result<impl IntoResponse, HandlerError> {
    // Add sponsor to database
    db.add_group_sponsor(group_id, &sponsor).await?;

    Ok((
        StatusCode::CREATED,
        [(
            "HX-Trigger",
            "refresh-sponsors-table,refresh-group-dashboard-table",
        )],
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
        [(
            "HX-Trigger",
            "refresh-sponsors-table,refresh-group-dashboard-table",
        )],
    ))
}

/// Updates an existing sponsor in the database.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(group_sponsor_id): Path<Uuid>,
    Form(sponsor): Form<Sponsor>,
) -> Result<impl IntoResponse, HandlerError> {
    // Update sponsor in database
    db.update_group_sponsor(group_id, group_sponsor_id, &sponsor).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [(
            "HX-Trigger",
            "refresh-sponsors-table,refresh-group-dashboard-table",
        )],
    ))
}
