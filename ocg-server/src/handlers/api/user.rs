//! Authenticated user API handlers.

use axum::{
    Json,
    extract::{Path, State},
    response::IntoResponse,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    handlers::extractors::ValidatedJson,
    router,
    templates::auth::UserDetails,
    types::{jobs::JobApplicationInput, questionnaire::QuestionnaireAnswers},
};

use super::auth::{ApiScope, ApiUser};
use super::{
    error::ApiError,
    types::{ApiResponse, EmptyData},
};

pub(crate) async fn me(api_user: ApiUser) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(ApiResponse::data(api_user.user)))
}

pub(crate) async fn update_me(
    State(state): State<router::State>,
    api_user: ApiUser,
    ValidatedJson(input): ValidatedJson<UserDetails>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteProfile)?;
    state.db.update_user_details(&api_user.user_id(), &input).await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

pub(crate) async fn join_group(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<GroupActionPath>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteEvents)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    state
        .db
        .join_group(alliance_id, path.group_id, api_user.user_id())
        .await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

pub(crate) async fn leave_group(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<GroupActionPath>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteEvents)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    state
        .db
        .leave_group(alliance_id, path.group_id, api_user.user_id())
        .await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

pub(crate) async fn event_attendance(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<EventActionPath>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteEvents)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    let attendance = state
        .db
        .get_event_attendance(alliance_id, path.event_id, api_user.user_id())
        .await?;
    Ok(Json(ApiResponse::data(attendance)))
}

pub(crate) async fn attend_event(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<EventActionPath>,
    body: Option<Json<AttendEventInput>>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteEvents)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    let answers = body.and_then(|Json(input)| input.registration_answers);
    let status = state
        .db
        .attend_event(alliance_id, path.event_id, api_user.user_id(), answers)
        .await?;
    Ok(Json(ApiResponse::data(status)))
}

pub(crate) async fn leave_event(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<EventActionPath>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteEvents)?;
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    let outcome = state
        .db
        .leave_event(alliance_id, path.event_id, api_user.user_id())
        .await?;
    Ok(Json(ApiResponse::data(outcome)))
}

pub(crate) async fn apply_to_job(
    State(state): State<router::State>,
    api_user: ApiUser,
    Path(path): Path<JobActionPath>,
    ValidatedJson(input): ValidatedJson<JobApplicationInput>,
) -> Result<impl IntoResponse, ApiError> {
    api_user.require_scope(ApiScope::WriteJobs)?;
    state
        .db
        .add_job_application(api_user.user_id(), path.job_id, &input)
        .await?;
    Ok(Json(ApiResponse::data(EmptyData {})))
}

async fn alliance_id(state: &router::State, alliance: &str) -> Result<Uuid, ApiError> {
    state
        .db
        .get_alliance_id_by_name(alliance)
        .await?
        .ok_or_else(ApiError::not_found)
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct GroupActionPath {
    alliance: String,
    group_id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct EventActionPath {
    alliance: String,
    event_id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct JobActionPath {
    job_id: Uuid,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct AttendEventInput {
    registration_answers: Option<QuestionnaireAnswers>,
}
