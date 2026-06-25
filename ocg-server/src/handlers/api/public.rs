//! Public API read handlers.

use axum::{
    Json,
    extract::{Path, Query, RawQuery, State},
    http::{HeaderMap, StatusCode, header::AUTHORIZATION},
    response::IntoResponse,
};
use garde::Validate;
use serde::{Deserialize, Serialize};

use crate::{
    db::common::SearchEventsOutput,
    router,
    templates::site::explore::Entity,
    types::{
        jobs::{JobsFilters, JobsOutput},
        landscape::{LandscapeFilters, LandscapeOutput},
        search::{SearchEventsFilters, SearchGroupsFilters},
    },
};

use super::auth::hash_token;
use super::{error::ApiError, types::ApiResponse};

/// Public API health check.
pub(crate) async fn health() -> impl IntoResponse {
    Json(ApiResponse::data(serde_json::json!({ "status": "ok" })))
}

pub(crate) async fn filters(
    State(state): State<router::State>,
    Query(query): Query<FiltersQuery>,
) -> Result<impl IntoResponse, ApiError> {
    let filters = state.db.get_filters_options(query.alliance, query.entity).await?;
    Ok(Json(ApiResponse::data(filters)))
}

pub(crate) async fn alliances(
    State(state): State<router::State>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(ApiResponse::data(state.db.list_alliances().await?)))
}

pub(crate) async fn alliance(
    State(state): State<router::State>,
    Path(path): Path<AlliancePath>,
) -> Result<impl IntoResponse, ApiError> {
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    Ok(Json(ApiResponse::data(
        state.db.get_alliance_full(alliance_id).await?,
    )))
}

pub(crate) async fn alliance_groups(
    State(state): State<router::State>,
    headers: HeaderMap,
    Path(path): Path<AlliancePath>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, ApiError> {
    let mut filters = SearchGroupsFilters::new(&headers, raw_query.as_deref().unwrap_or(""))?;
    filters.alliance = vec![path.alliance];
    let output = state.db.search_groups(&filters).await?;
    Ok(Json(
        ApiResponse::data(output.groups).with_meta("total", output.total),
    ))
}

pub(crate) async fn alliance_events(
    State(state): State<router::State>,
    headers: HeaderMap,
    Path(path): Path<AlliancePath>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, ApiError> {
    let mut filters = SearchEventsFilters::new(&headers, raw_query.as_deref().unwrap_or(""))?;
    filters.alliance = vec![path.alliance];
    let output = state.db.search_events(&filters).await?;
    Ok(Json(
        ApiResponse::data(output.events).with_meta("total", output.total),
    ))
}

pub(crate) async fn group(
    State(state): State<router::State>,
    Path(path): Path<GroupPath>,
) -> Result<impl IntoResponse, ApiError> {
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    let group = state
        .db
        .get_group_full_by_slug(alliance_id, &path.group_slug)
        .await?
        .ok_or_else(ApiError::not_found)?;
    Ok(Json(ApiResponse::data(group)))
}

pub(crate) async fn event(
    State(state): State<router::State>,
    Path(path): Path<EventPath>,
) -> Result<impl IntoResponse, ApiError> {
    let alliance_id = alliance_id(&state, &path.alliance).await?;
    let event = state
        .db
        .get_event_full_by_slug(alliance_id, &path.group_slug, &path.event_slug)
        .await?
        .ok_or_else(ApiError::not_found)?;
    Ok(Json(ApiResponse::data(event)))
}

pub(crate) async fn jobs(
    State(state): State<router::State>,
    Query(filters): Query<JobsFilters>,
) -> Result<impl IntoResponse, ApiError> {
    filters.validate().map_err(|error| validation_error(&error))?;
    let output = state.db.search_jobs(&filters).await?;
    Ok(Json(jobs_response(output)))
}

pub(crate) async fn job(
    State(state): State<router::State>,
    headers: HeaderMap,
    Path(path): Path<JobPath>,
) -> Result<impl IntoResponse, ApiError> {
    let viewer_user_id = optional_api_user_id(&state, &headers).await?;
    let job = state.db.get_job_by_slug(&path.slug, viewer_user_id).await?;
    Ok(Json(ApiResponse::data(job)))
}

pub(crate) async fn landscape(
    State(state): State<router::State>,
    Query(filters): Query<LandscapeFilters>,
) -> Result<impl IntoResponse, ApiError> {
    filters.validate().map_err(|error| validation_error(&error))?;
    let output = state.db.search_landscape_entries(&filters).await?;
    Ok(Json(landscape_response(output)))
}

pub(crate) async fn search(
    State(state): State<router::State>,
    headers: HeaderMap,
    Query(query): Query<SearchQuery>,
) -> Result<impl IntoResponse, ApiError> {
    query.validate().map_err(|error| validation_error(&error))?;
    let raw_query = format!("ts_query={}&limit={}", query.q, query.limit.unwrap_or(5));
    let mut events_filters = SearchEventsFilters::new(&headers, &raw_query)?;
    let mut groups_filters = SearchGroupsFilters::new(&headers, &raw_query)?;
    if let Some(alliance) = query.alliance.clone() {
        events_filters.alliance = vec![alliance.clone()];
        groups_filters.alliance = vec![alliance];
    }

    let jobs_filters = JobsFilters {
        query: Some(query.q.clone()),
        limit: query.limit,
        ..Default::default()
    };
    let landscape_filters = LandscapeFilters {
        query: Some(query.q),
        alliance: query.alliance,
        limit: query.limit,
        ..Default::default()
    };

    let (events, groups, jobs, landscape) = tokio::try_join!(
        state.db.search_events(&events_filters),
        state.db.search_groups(&groups_filters),
        state.db.search_jobs(&jobs_filters),
        state.db.search_landscape_entries(&landscape_filters),
    )?;

    Ok(Json(ApiResponse::data(SearchOutput {
        events: events_response(events),
        groups: groups.groups,
        jobs: jobs.jobs,
        landscape: landscape.entries,
    })))
}

async fn alliance_id(state: &router::State, alliance: &str) -> Result<uuid::Uuid, ApiError> {
    state
        .db
        .get_alliance_id_by_name(alliance)
        .await?
        .ok_or_else(ApiError::not_found)
}

fn validation_error(error: &garde::Report) -> ApiError {
    ApiError::new(
        StatusCode::UNPROCESSABLE_ENTITY,
        "validation_failed",
        "Request parameters failed validation.",
    )
    .with_details(vec![error.to_string()])
}

fn jobs_response(output: JobsOutput) -> ApiResponse<Vec<crate::types::jobs::JobSummary>> {
    ApiResponse::data(output.jobs).with_meta("total", output.total)
}

fn landscape_response(
    output: LandscapeOutput,
) -> ApiResponse<Vec<crate::types::landscape::LandscapeEntry>> {
    ApiResponse::data(output.entries).with_meta("total", output.total)
}

fn events_response(output: SearchEventsOutput) -> Vec<crate::types::event::EventSummary> {
    output.events
}

async fn optional_api_user_id(
    state: &router::State,
    headers: &HeaderMap,
) -> Result<Option<uuid::Uuid>, ApiError> {
    let Some(header) = headers.get(AUTHORIZATION) else {
        return Ok(None);
    };
    let Ok(header) = header.to_str() else {
        return Ok(None);
    };
    let Some(token) = header.strip_prefix("Bearer ") else {
        return Ok(None);
    };
    Ok(state
        .db
        .get_api_token_auth(&hash_token(token))
        .await?
        .map(|api_user| api_user.user_id()))
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct FiltersQuery {
    alliance: Option<String>,
    entity: Option<Entity>,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct AlliancePath {
    alliance: String,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct GroupPath {
    alliance: String,
    group_slug: String,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct EventPath {
    alliance: String,
    group_slug: String,
    event_slug: String,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct JobPath {
    slug: String,
}

#[derive(Debug, Clone, Deserialize, Validate)]
pub(crate) struct SearchQuery {
    #[garde(length(min = 1, max = 200))]
    q: String,
    #[garde(length(max = 200))]
    alliance: Option<String>,
    #[serde(default)]
    #[garde(range(max = 50))]
    limit: Option<usize>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct SearchOutput {
    events: Vec<crate::types::event::EventSummary>,
    groups: Vec<crate::types::group::GroupSummary>,
    jobs: Vec<crate::types::jobs::JobSummary>,
    landscape: Vec<crate::types::landscape::LandscapeEntry>,
}

#[cfg(test)]
mod tests {
    use axum::{body, response::IntoResponse};

    use super::health;

    #[tokio::test]
    async fn health_returns_ok_json_envelope() {
        let response = health().await.into_response();

        assert!(response.status().is_success());

        let body = body::to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("body bytes");
        let body: serde_json::Value = serde_json::from_slice(&body).expect("valid json");

        assert_eq!(body["data"]["status"], "ok");
    }
}
