//! HTTP handlers for the group site.

use askama::Template;
use axum::{
    Json,
    extract::{Path, RawQuery, State},
    http::{HeaderMap, HeaderValue, StatusCode, Uri, header::CACHE_CONTROL},
    response::{Html, IntoResponse, Redirect},
};
use serde_json::json;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    activity_tracker::{Activity, DynActivityTracker},
    auth::AuthSession,
    config::HttpServerConfig,
    db::DynDB,
    handlers::{
        extractors::{CurrentUser, ValidatedForm},
        request_matches_site, site::not_found, trim_public_gallery_images,
    },
    router::{CACHE_CONTROL_PRIVATE_NO_STORE, PUBLIC_SHARED_CACHE_HEADERS, serde_qs_config},
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::{
        PageId,
        auth::User,
        dashboard::group::accelerator::{
            AcceleratorApplicationInput, AcceleratorWeeklyUpdateInput,
        },
        dashboard::group::members::GroupMembersFilters,
        group::{self, AcceleratorPage, MembersPage, Page, ReportPage, SpotlightsPage, StorePage},
        notifications::{GroupWelcome, MockInterviewMatched},
    },
    types::{
        event::EventKind,
        group::{GroupFull, GroupJoinOutcome},
        mock_interviews::{MockInterviewMatchNotificationContext, option_label},
        pagination::NavigationLinks,
        site::SiteSettings,
    },
};

use super::{error::HandlerError, extractors::AllianceId};

#[cfg(test)]
mod tests;

// Pages handlers.

/// Handler that renders the group home page.
#[instrument(skip_all)]
pub(crate) async fn page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Get alliance and site settings
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    // Fetch the group page data
    let event_kinds = vec![EventKind::InPerson, EventKind::Virtual, EventKind::Hybrid];
    let (group, past_events, upcoming_events) = tokio::try_join!(
        db.get_group_full_by_slug(alliance_id, &group_slug),
        db.get_group_past_events(alliance_id, &group_slug, event_kinds.clone(), 9),
        db.get_group_upcoming_events(alliance_id, &group_slug, event_kinds, 9)
    )?;
    let Some(mut group) = group else {
        return not_found::render(site_settings);
    };

    // Redirect generated group slugs to their pretty URL
    if should_redirect_to_pretty_group_slug(&group, &group_slug) {
        let url = public_group_url(&alliance_name, group.public_slug(), &uri);
        return Ok(Redirect::temporary(&url).into_response());
    }

    // Trim gallery media
    trim_public_gallery_images(&mut group.photos_urls);

    // Only display featured sponsors on the group page
    group.sponsors.retain(|sponsor| sponsor.featured);

    let (accelerator, spotlights, store_items) = tokio::try_join!(
        db.get_group_accelerator_dashboard(group.group_id),
        db.list_group_member_spotlights(group.group_id, false),
        db.list_group_store_items(group.group_id, false)
    )?;
    let has_accelerator = accelerator.programs.iter().any(|program| program.active)
        || !accelerator.cohorts.is_empty();

    // Prepare the page template
    let template = Page {
        base_url: server_cfg.base_url,
        group,
        has_accelerator,
        page_id: PageId::Group,
        past_events: past_events
            .into_iter()
            .map(|event| group::PastEventCard { event })
            .collect(),
        path: uri.path().to_string(),
        site_settings,
        spotlights,
        store_items,
        upcoming_events: upcoming_events
            .into_iter()
            .map(|event| group::UpcomingEventCard { event })
            .collect(),
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

/// Handler that renders the public group accelerator page.
#[instrument(skip_all)]
pub(crate) async fn accelerator_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let Some(mut group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return not_found::render(site_settings);
    };

    trim_public_gallery_images(&mut group.photos_urls);
    group.sponsors.clear();
    let accelerator = db.get_group_accelerator_dashboard(group.group_id).await?;

    let user = User::from_session(auth_session).await?;
    let headers = public_group_page_headers(&user);
    let template = AcceleratorPage {
        base_url: server_cfg.base_url,
        accelerator,
        group,
        page_id: PageId::Group,
        path: uri.path().to_string(),
        site_settings,
        user,
    };

    Ok((headers, Html(template.render()?)).into_response())
}

/// Submits an application to an accelerator cohort.
#[instrument(skip_all, err)]
pub(crate) async fn apply_to_accelerator_cohort(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((_alliance_name, group_id, cohort_id)): Path<(String, Uuid, Uuid)>,
    ValidatedForm(input): ValidatedForm<AcceleratorApplicationInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.submit_group_accelerator_application(user.user_id, group_id, cohort_id, &input)
        .await?;

    Ok((
        StatusCode::CREATED,
        [(
            "HX-Trigger",
            "accelerator-application-submitted, refresh-body",
        )],
        Html(
            r#"<div class="rounded-2xl border border-primary-200 bg-primary-50 px-4 py-5 text-sm/6 text-primary-900">
  <div class="font-bold">Application submitted.</div>
  <p class="mt-1">The accelerator team can now review your project from the group dashboard.</p>
</div>"#,
        ),
    ))
}

/// Submits a weekly update for an accepted accelerator member.
#[instrument(skip_all, err)]
pub(crate) async fn submit_accelerator_weekly_update(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((_alliance_name, group_id, week_id)): Path<(String, Uuid, Uuid)>,
    ValidatedForm(input): ValidatedForm<AcceleratorWeeklyUpdateInput>,
) -> Result<impl IntoResponse, HandlerError> {
    db.submit_group_accelerator_weekly_update(user.user_id, group_id, week_id, &input)
        .await?;

    Ok((
        StatusCode::CREATED,
        [("HX-Trigger", "accelerator-weekly-update-submitted")],
    ))
}

/// Handler that renders logged-in group member spotlights.
#[instrument(skip_all)]
pub(crate) async fn spotlights_page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let Some(mut group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return not_found::render(site_settings);
    };
    trim_public_gallery_images(&mut group.photos_urls);
    group.sponsors.clear();

    let spotlights = db.list_group_member_spotlights(group.group_id, false).await?;
    let template = SpotlightsPage {
        base_url: server_cfg.base_url,
        group,
        page_id: PageId::Group,
        path: uri.path().to_string(),
        site_settings,
        spotlights,
        user: User::from_session(auth_session).await?,
    };

    Ok(Html(template.render()?).into_response())
}

/// Handler that renders the public group report page.
#[instrument(skip_all)]
pub(crate) async fn report_page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let Some(mut group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return not_found::render(site_settings);
    };
    if !group.report_public_enabled {
        return not_found::render(site_settings);
    }

    trim_public_gallery_images(&mut group.photos_urls);
    group.sponsors.clear();
    let stats = db.get_group_stats(alliance_id, group.group_id).await?;
    let template = ReportPage {
        base_url: server_cfg.base_url,
        group,
        page_id: PageId::Group,
        path: uri.path().to_string(),
        site_settings,
        stats,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

/// Handler that renders a logged-in group member directory.
#[instrument(skip_all)]
pub(crate) async fn members_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    RawQuery(raw_query): RawQuery,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let Some(mut group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return not_found::render(site_settings);
    };
    trim_public_gallery_images(&mut group.photos_urls);
    group.sponsors.clear();

    let is_member = db.is_group_member(alliance_id, group.group_id, user.user_id).await?;
    if !is_member {
        return Ok((
            StatusCode::FORBIDDEN,
            "Join this group first to see members.",
        )
            .into_response());
    }

    let filters: GroupMembersFilters =
        serde_qs_config().deserialize_str(raw_query.as_deref().unwrap_or_default())?;
    let results = db
        .list_group_members(group.group_id, user.user_id, false, &filters)
        .await?;
    let page_url = format!(
        "/{}/group/{}/members",
        group.alliance.name,
        group.public_slug()
    );
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, &page_url, &page_url)?;
    let template_user = User {
        logged_in: true,
        auth_provider: None,
        belongs_to_any_group_team: user.belongs_to_any_group_team,
        belongs_to_alliance_team: user.belongs_to_alliance_team,
        name: Some(user.name),
        platform_admin: user.platform_admin,
        username: Some(user.username),
    };

    let template = MembersPage {
        base_url: server_cfg.base_url,
        group,
        members: results.members,
        navigation_links,
        offset: filters.offset,
        page_id: PageId::Group,
        path: uri.path().to_string(),
        query: filters.query.clone(),
        site_settings,
        total: results.total,
        user: template_user,
    };

    Ok(Html(template.render()?).into_response())
}

/// Requests access to another group member's phone number from the member directory.
#[instrument(skip_all)]
pub(crate) async fn request_member_phone(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((alliance_name, group_slug, recipient_user_id)): Path<(String, String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    let Some(alliance_id) = db.get_alliance_id_by_name(&alliance_name).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };
    let Some(group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    if !db.is_group_member(alliance_id, group.group_id, user.user_id).await? {
        return Ok(StatusCode::FORBIDDEN.into_response());
    }

    db.request_group_member_phone(user.user_id, group.group_id, recipient_user_id)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Refresh", "true")]).into_response())
}

/// Requests another group member as a mock interview interviewer.
#[instrument(skip_all)]
pub(crate) async fn request_member_mock_interview(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    State(notifications_manager): State<DynNotificationsManager>,
    Path((alliance_name, group_slug, interviewer_user_id)): Path<(String, String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    if user.user_id == interviewer_user_id {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    }

    let Some(alliance_id) = db.get_alliance_id_by_name(&alliance_name).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };
    let Some(group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    if !group.mock_interviews_available() {
        return Ok(StatusCode::NOT_FOUND.into_response());
    }

    let match_id = db
        .request_group_mock_interviewer(user.user_id, alliance_id, group.group_id, interviewer_user_id)
        .await?;

    let Some(match_id) = match_id else {
        return Ok(StatusCode::FORBIDDEN.into_response());
    };

    let context = db
        .get_mock_interview_match_notification_context(match_id)
        .await?
        .ok_or(HandlerError::NotFound)?;
    let site_settings = db.get_site_settings().await?;
    enqueue_mock_interview_match_notifications(
        &notifications_manager,
        &server_cfg,
        &site_settings,
        &context,
    )
    .await;

    Ok((StatusCode::NO_CONTENT, [("HX-Refresh", "true")]).into_response())
}

async fn enqueue_mock_interview_match_notifications(
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    site_settings: &SiteSettings,
    context: &MockInterviewMatchNotificationContext,
) {
    let Some(host_user_id) = context.interviewer_user_id else {
        warn!(
            match_id = %context.mock_interview_match_id,
            "mock interview match notification skipped because interviewer is missing"
        );
        return;
    };
    let Some(candidate_user_id) = context.interviewee_user_id else {
        warn!(
            match_id = %context.mock_interview_match_id,
            "mock interview match notification skipped because interviewee is missing"
        );
        return;
    };

    let dashboard_link = format!(
        "{}/dashboard/user?tab=mock-interviews",
        server_cfg
            .base_url
            .strip_suffix('/')
            .unwrap_or(&server_cfg.base_url)
    );
    let interview_type = option_label(&context.interview_type).to_string();
    let notifications = [
        (
            host_user_id,
            MockInterviewMatched {
                dashboard_link: dashboard_link.clone(),
                interview_type: interview_type.clone(),
                recipient_role: "interviewer".to_string(),
                partner_name: context.interviewee_label(),
                partner_username: context.interviewee_username.clone(),
                theme: site_settings.theme.clone(),
            },
        ),
        (
            candidate_user_id,
            MockInterviewMatched {
                dashboard_link,
                interview_type,
                recipient_role: "interviewee".to_string(),
                partner_name: context.interviewer_label(),
                partner_username: context.interviewer_username.clone(),
                theme: site_settings.theme.clone(),
            },
        ),
    ];

    for (recipient, template_data) in notifications {
        let notification = NewNotification {
            attachments: vec![],
            kind: NotificationKind::MockInterviewMatched,
            recipients: vec![recipient],
            template_data: match serde_json::to_value(&template_data) {
                Ok(value) => Some(value),
                Err(err) => {
                    warn!(error = %err, "failed to serialize mock interview match notification");
                    continue;
                }
            },
        };
        if let Err(err) = notifications_manager.enqueue(&notification).await {
            warn!(
                error = %err,
                recipient = %recipient,
                "failed to enqueue mock interview match notification"
            );
        }
    }
}

/// Approves a pending phone visibility request for the current member.
#[instrument(skip_all)]
pub(crate) async fn approve_member_phone_request(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    Path((alliance_name, group_slug, requester_user_id)): Path<(String, String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    let Some(alliance_id) = db.get_alliance_id_by_name(&alliance_name).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };
    let Some(group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    if !db.is_group_member(alliance_id, group.group_id, user.user_id).await? {
        return Ok(StatusCode::FORBIDDEN.into_response());
    }

    db.approve_group_member_phone_request(user.user_id, group.group_id, requester_user_id)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Refresh", "true")]).into_response())
}

/// Handler that renders the public group store page.
#[instrument(skip_all)]
pub(crate) async fn store_page(
    State(db): State<DynDB>,
    State(server_cfg): State<HttpServerConfig>,
    Path((alliance_name, group_slug)): Path<(String, String)>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    let (alliance_id, site_settings) = tokio::try_join!(
        db.get_alliance_id_by_name(&alliance_name),
        db.get_site_settings()
    )?;
    let Some(alliance_id) = alliance_id else {
        return not_found::render(site_settings);
    };

    let Some(mut group) = db.get_group_full_by_slug(alliance_id, &group_slug).await? else {
        return not_found::render(site_settings);
    };
    trim_public_gallery_images(&mut group.photos_urls);
    group.sponsors.retain(|sponsor| sponsor.featured);

    let store_items = db.list_group_store_items(group.group_id, false).await?;
    let template = StorePage {
        base_url: server_cfg.base_url,
        group,
        page_id: PageId::Group,
        path: uri.path().to_string(),
        site_settings,
        store_items,
        user: User::default(),
    };

    Ok((PUBLIC_SHARED_CACHE_HEADERS, Html(template.render()?)).into_response())
}

// Helpers.

/// Returns cache headers for public group pages, avoiding shared caches for personalized content.
fn public_group_page_headers(user: &User) -> HeaderMap {
    let mut headers = HeaderMap::new();

    if user.logged_in {
        headers.insert(
            CACHE_CONTROL,
            HeaderValue::from_static(CACHE_CONTROL_PRIVATE_NO_STORE),
        );
        return headers;
    }

    for (key, value) in PUBLIC_SHARED_CACHE_HEADERS {
        headers.insert(key, HeaderValue::from_static(value));
    }

    headers
}

/// Builds a public group URL with the original query string, if present.
fn public_group_url(alliance_name: &str, group_slug: &str, uri: &Uri) -> String {
    let mut url = format!("/{alliance_name}/group/{group_slug}");
    if let Some(query) = uri.query() {
        url.push('?');
        url.push_str(query);
    }

    url
}

/// Returns whether a public group request should redirect to a pretty group slug.
fn should_redirect_to_pretty_group_slug(group: &GroupFull, group_slug: &str) -> bool {
    group.slug_pretty.is_some() && group_slug == group.slug
}

// Actions handlers.

/// Handler for joining a group.
#[instrument(skip_all)]
pub(crate) async fn join_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    State(notifications_manager): State<DynNotificationsManager>,
    State(server_cfg): State<HttpServerConfig>,
    AllianceId(alliance_id): AllianceId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Join immediately or create a pending approval request.
    let outcome = db.join_group(alliance_id, group_id, user.user_id).await?;

    if outcome == GroupJoinOutcome::Joined {
        // Enqueue welcome notification best-effort after the membership mutation.
        if let Err(err) = async {
            let (site_settings, group) = tokio::try_join!(
                db.get_site_settings(),
                db.get_group_summary(alliance_id, group_id)
            )?;
            let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
            let template_data = GroupWelcome {
                link: format!(
                    "{}/{}/group/{}",
                    base_url,
                    group.alliance_name,
                    group.public_slug()
                ),
                group,
                theme: site_settings.theme,
            };
            let notification = NewNotification {
                attachments: vec![],
                kind: NotificationKind::GroupWelcome,
                recipients: vec![user.user_id],
                template_data: Some(serde_json::to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await
        }
        .await
        {
            warn!(
                error = %err,
                %alliance_id,
                %group_id,
                user_id = %user.user_id,
                "failed to enqueue group welcome notification"
            );
        }
    }

    Ok(Json(json!({ "status": outcome })))
}

/// Handler for leaving a group.
#[instrument(skip_all)]
pub(crate) async fn leave_group(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Leave the group
    db.leave_group(alliance_id, group_id, user.user_id).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Handler for checking group membership status.
#[instrument(skip_all)]
pub(crate) async fn membership_status(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    AllianceId(alliance_id): AllianceId,
    Path((_, group_id)): Path<(String, Uuid)>,
) -> Result<impl IntoResponse, HandlerError> {
    // Check membership.
    let status = db
        .get_group_membership_status(alliance_id, group_id, user.user_id)
        .await?;
    let Some(status) = status else {
        return Ok(StatusCode::NOT_FOUND.into_response());
    };

    Ok(Json(status).into_response())
}

/// Tracks a group page view.
#[instrument(skip_all)]
pub(crate) async fn track_view(
    headers: HeaderMap,
    State(activity_tracker): State<DynActivityTracker>,
    State(server_cfg): State<HttpServerConfig>,
    Path(group_id): Path<Uuid>,
) -> Result<impl IntoResponse, HandlerError> {
    if request_matches_site(&server_cfg, &headers)? {
        activity_tracker.track(Activity::GroupView { group_id }).await?;
    }

    Ok(StatusCode::NO_CONTENT)
}
