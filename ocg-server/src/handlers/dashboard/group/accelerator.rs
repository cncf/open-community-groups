//! HTTP handlers for group accelerator management.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::{HeaderName, StatusCode},
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, SelectedGroupId, ValidatedForm},
    },
    templates::dashboard::group::accelerator::{
        self, AcceleratorApplicationReviewInput, AcceleratorCohortInput, AcceleratorProgramInput,
        AcceleratorWeekInput, AcceleratorWeeklyUpdateReviewInput,
    },
    types::permissions::GroupPermission,
};

const DASHBOARD_URL: &str = "/dashboard/group?tab=accelerator";

/// Displays the accelerator dashboard.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let template = prepare_page(&db, alliance_id, group_id, user.user_id).await?;
    let headers = [(
        HeaderName::from_static("hx-push-url"),
        DASHBOARD_URL.to_string(),
    )];

    Ok((headers, Html(template.render()?)))
}

/// Adds an accelerator program.
#[instrument(skip_all, err)]
pub(crate) async fn add_program(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<AcceleratorProgramInput>,
) -> Result<impl IntoResponse, HandlerError> {
    ensure_can_manage_accelerator(&db, alliance_id, group_id, user.user_id).await?;
    db.add_group_accelerator_program(user.user_id, group_id, &input)
        .await?;

    Ok(refresh_created())
}

/// Adds a cohort.
#[instrument(skip_all, err)]
pub(crate) async fn add_cohort(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<AcceleratorCohortInput>,
) -> Result<impl IntoResponse, HandlerError> {
    ensure_can_manage_accelerator(&db, alliance_id, group_id, user.user_id).await?;
    db.add_group_accelerator_cohort(user.user_id, group_id, &input)
        .await?;

    Ok(refresh_created())
}

/// Adds or updates a curriculum week.
#[instrument(skip_all, err)]
pub(crate) async fn add_week(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<AcceleratorWeekInput>,
) -> Result<impl IntoResponse, HandlerError> {
    ensure_can_manage_accelerator(&db, alliance_id, group_id, user.user_id).await?;
    db.add_group_accelerator_week(user.user_id, group_id, &input).await?;

    Ok(refresh_created())
}

/// Reviews an application.
#[instrument(skip_all, err)]
pub(crate) async fn review_application(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(application_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<AcceleratorApplicationReviewInput>,
) -> Result<impl IntoResponse, HandlerError> {
    ensure_can_manage_accelerator(&db, alliance_id, group_id, user.user_id).await?;
    db.review_group_accelerator_application(user.user_id, group_id, application_id, &input)
        .await?;

    Ok(refresh_no_content())
}

/// Accepts an application and creates a cohort member.
#[instrument(skip_all, err)]
pub(crate) async fn accept_application(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(application_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    ensure_can_manage_accelerator(&db, alliance_id, group_id, user.user_id).await?;
    db.accept_group_accelerator_application(user.user_id, group_id, application_id)
        .await?;

    Ok(refresh_no_content())
}

/// Reviews a weekly update.
#[instrument(skip_all, err)]
pub(crate) async fn review_weekly_update(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    SelectedGroupId(group_id): SelectedGroupId,
    State(db): State<DynDB>,
    Path(weekly_update_id): Path<Uuid>,
    ValidatedForm(input): ValidatedForm<AcceleratorWeeklyUpdateReviewInput>,
) -> Result<impl IntoResponse, HandlerError> {
    ensure_can_manage_accelerator(&db, alliance_id, group_id, user.user_id).await?;
    db.review_group_accelerator_weekly_update(user.user_id, group_id, weekly_update_id, &input)
        .await?;

    Ok(refresh_no_content())
}

/// Prepares the accelerator dashboard template.
pub(crate) async fn prepare_page(
    db: &DynDB,
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
) -> Result<accelerator::Page, HandlerError> {
    let (can_manage_accelerator, dashboard) = tokio::try_join!(
        db.user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::EventsWrite,
        ),
        db.get_group_accelerator_dashboard(group_id),
    )?;

    Ok(accelerator::Page {
        can_manage_accelerator,
        programs: dashboard.programs,
        cohorts: dashboard.cohorts,
        applications: dashboard.applications,
        members: dashboard.members,
        weeks: dashboard.weeks,
        weekly_updates: dashboard.weekly_updates,
    })
}

async fn ensure_can_manage_accelerator(
    db: &DynDB,
    alliance_id: Uuid,
    group_id: Uuid,
    user_id: Uuid,
) -> Result<(), HandlerError> {
    let can_manage = db
        .user_has_group_permission(
            &alliance_id,
            &group_id,
            &user_id,
            GroupPermission::EventsWrite,
        )
        .await?;

    if !can_manage {
        return Err(HandlerError::Forbidden);
    }

    Ok(())
}

fn refresh_created() -> impl IntoResponse {
    (
        StatusCode::CREATED,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
}

fn refresh_no_content() -> impl IntoResponse {
    (
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-group-dashboard-table")],
    )
}
