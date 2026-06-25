//! Admin API mutation handlers.

use std::collections::HashMap;

use axum::{
    Json,
    extract::{Path, State},
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{
    config::MeetingsConfig,
    handlers::extractors::ValidatedJson,
    router,
    services::meetings::MeetingProvider,
    templates::dashboard::{
        alliance::{create::AllianceCreate, groups::Group, settings::AllianceUpdate},
        group::events::Event,
    },
    types::{jobs::JobInput, landscape::LandscapeEntryInput},
};

use super::auth::{ApiScope, ApiUser};
use super::{
    error::ApiError,
    types::{ApiResponse, EmptyData},
};

pub(crate) async fn create_alliance(
    State(state): State<router::State>,
    api_user: ApiUser,
    ValidatedJson(input): ValidatedJson<AllianceCreate>,
) -> Result<impl IntoResponse, ApiError> {
    require_platform_admin(&api_user)?;
    let id = state.db.add_alliance(api_user.user_id(), &input).await?;
    Ok(Json(ApiResponse::data(IdOutput { id })))
}

pub(crate) async fn update_alliance(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<AlliancePath>,
    ValidatedJson(input): ValidatedJson<AllianceUpdate>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::AdminAlliance)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    state
        .db
        .update_alliance(api_user.user_id(), alliance_id, &input)
        .await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

pub(crate) async fn create_group(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<AlliancePath>,
    ValidatedJson(input): ValidatedJson<Group>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::AdminAlliance)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    let id = state.db.add_group(api_user.user_id(), alliance_id, &input).await?;
    Ok(Json(ApiResponse::data(IdOutput { id })))
}

pub(crate) async fn update_group(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<GroupPath>,
    ValidatedJson(input): ValidatedJson<Group>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::AdminAlliance)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    state
        .db
        .update_group(api_user.user_id(), alliance_id, path.group_id, &input)
        .await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

pub(crate) async fn create_event(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<CreateEventPath>,
    ValidatedJson(input): ValidatedJson<Event>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteEvents)?;
    let payload = input.to_db_payload()?;
    let id = state
        .db
        .add_event(
            api_user.user_id(),
            path.group_id,
            &payload,
            &build_meetings_max_participants(state.meetings_cfg.as_ref()),
        )
        .await?;
    Ok(Json(ApiResponse::data(IdOutput { id })))
}

pub(crate) async fn update_event(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<EventPath>,
    ValidatedJson(input): ValidatedJson<Event>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteEvents)?;
    let group_id = state
        .db
        .get_event_group_id(path.event_id)
        .await?
        .ok_or_else(ApiError::not_found)?;
    let payload = input.to_db_payload()?;
    let promoted_user_ids = state
        .db
        .update_event(
            api_user.user_id(),
            group_id,
            path.event_id,
            &payload,
            &build_meetings_max_participants(state.meetings_cfg.as_ref()),
        )
        .await?;
    Ok(Json(ApiResponse::data(promoted_user_ids)))
}

pub(crate) async fn create_job(
    State(state): State<router::State>,
    api_user: ApiUser,
    ValidatedJson(input): ValidatedJson<JobInput>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteJobs)?;
    let id = state.db.add_job(api_user.user_id(), &input).await?;
    Ok(Json(ApiResponse::data(IdOutput { id })))
}

pub(crate) async fn update_job(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<JobPath>,
    ValidatedJson(input): ValidatedJson<JobInput>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteJobs)?;
    state.db.update_job(api_user.user_id(), path.job_id, &input).await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

pub(crate) async fn delete_job(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<JobPath>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteJobs)?;
    state.db.delete_job(api_user.user_id(), path.job_id).await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

pub(crate) async fn create_landscape_entry(
    State(state): State<router::State>,
    api_user: ApiUser,
    ValidatedJson(input): ValidatedJson<LandscapeEntryApiInput>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::AdminAlliance)?;
    let alliance_id = alliance_id(&state, &input.alliance).await?;
    let id = state
        .db
        .add_landscape_entry(api_user.user_id(), alliance_id, &input.entry)
        .await?;
    Ok(Json(ApiResponse::data(IdOutput { id })))
}

pub(crate) async fn update_landscape_entry(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<LandscapePath>,
    ValidatedJson(input): ValidatedJson<LandscapeEntryApiInput>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::AdminAlliance)?;
    let alliance_id = alliance_id(&state, &input.alliance).await?;
    state
        .db
        .update_landscape_entry(api_user.user_id(), alliance_id, path.entry_id, &input.entry)
        .await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

fn require_platform_admin(api_user: &ApiUser) -> Result<(), ApiError> {
    api_user.require_scope(ApiScope::AdminPlatform)?;
    if api_user.user.platform_admin {
        return Ok(());
    }
    Err(ApiError::forbidden())
}

async fn alliance_id(state: &router::State, alliance: &str) -> Result<Uuid, ApiError> {
    state
        .db
        .get_alliance_id_by_name(alliance)
        .await?
        .ok_or_else(ApiError::not_found)
}

fn build_meetings_max_participants(
    meetings_cfg: Option<&MeetingsConfig>,
) -> HashMap<MeetingProvider, i32> {
    let mut map = HashMap::new();
    if let Some(cfg) = meetings_cfg
        && let Some(google_meet) = &cfg.google_meet
    {
        map.insert(MeetingProvider::GoogleMeet, google_meet.max_participants);
    }
    if let Some(cfg) = meetings_cfg
        && let Some(zoom) = &cfg.zoom
    {
        map.insert(MeetingProvider::Zoom, zoom.max_participants);
    }
    map
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct IdOutput {
    id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct AlliancePath {
    alliance: String,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct GroupPath {
    alliance: String,
    group_id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct CreateEventPath {
    group_id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct EventPath {
    event_id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct JobPath {
    job_id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct LandscapePath {
    entry_id: Uuid,
}

#[derive(Debug, Clone, Deserialize, garde::Validate)]
pub(crate) struct LandscapeEntryApiInput {
    #[garde(length(min = 1, max = 200))]
    alliance: String,
    #[serde(flatten)]
    #[garde(dive)]
    entry: LandscapeEntryInput,
}
