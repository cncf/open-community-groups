//! Common HTTP handlers shared across different dashboards.

use std::collections::HashMap;

use anyhow::{Result, anyhow};
use axum::{
    Json,
    extract::{Query, State},
    response::IntoResponse,
};
use reqwest::StatusCode;
use tracing::{instrument, warn};
use uuid::Uuid;

use crate::{
    config::HttpServerConfig,
    db::{DynDB, dashboard::common::IntentionalDatingOptIn},
    handlers::error::HandlerError,
    services::notifications::{DynNotificationsManager, NewNotification, NotificationKind},
    templates::notifications::IntentionalDatingIntroduction,
};

#[cfg(test)]
mod tests;

/// Searches for users by query.
#[instrument(skip_all, err)]
pub(crate) async fn search_user(
    State(db): State<DynDB>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<impl IntoResponse, HandlerError> {
    // Get search query from query parameters
    let Some(q) = query.get("q") else {
        return Ok(StatusCode::BAD_REQUEST.into_response());
    };

    // Search users in the database
    let users = db.search_user(q).await?;

    Ok(Json(users).into_response())
}

/// Enqueues optional notifications for an admin-curated intentional dating introduction.
pub(crate) async fn enqueue_intentional_dating_intro_notifications(
    db: &DynDB,
    notifications_manager: &DynNotificationsManager,
    server_cfg: &HttpServerConfig,
    alliance_id: Uuid,
    group_id: Uuid,
    first_user_id: Uuid,
    second_user_id: Uuid,
    notification_message: Option<&str>,
) {
    let Some(message) = notification_message else {
        return;
    };

    if let Err(err) = async {
        let (opt_ins, site_settings) = tokio::try_join!(
            db.list_intentional_dating_opt_ins(alliance_id, Some(group_id)),
            db.get_site_settings(),
        )?;
        let first = find_intro_opt_in(&opt_ins, first_user_id)?;
        let second = find_intro_opt_in(&opt_ins, second_user_id)?;
        let base_url = server_cfg.base_url.strip_suffix('/').unwrap_or(&server_cfg.base_url);
        let dashboard_link = format!("{base_url}/dashboard/user");

        for (recipient, partner) in [(first, second), (second, first)] {
            let template_data = IntentionalDatingIntroduction {
                alliance_display_name: recipient.alliance_display_name.clone(),
                dashboard_link: dashboard_link.clone(),
                group_name: recipient.group_name.clone(),
                message: message.to_string(),
                partner_name: opt_in_display_name(partner),
                partner_profile_url: format!("{base_url}/profiles/{}", partner.username),
                partner_username: partner.username.clone(),
                theme: site_settings.theme.clone(),
            };
            let notification = NewNotification {
                attachments: vec![],
                kind: NotificationKind::IntentionalDatingIntroduction,
                recipients: vec![recipient.user_id],
                template_data: Some(serde_json::to_value(&template_data)?),
            };
            notifications_manager.enqueue(&notification).await?;
        }

        Result::<()>::Ok(())
    }
    .await
    {
        warn!(
            error = %err,
            %alliance_id,
            %group_id,
            %first_user_id,
            %second_user_id,
            "failed to enqueue intentional dating introduction notifications"
        );
    }
}

fn find_intro_opt_in(
    opt_ins: &[IntentionalDatingOptIn],
    user_id: Uuid,
) -> Result<&IntentionalDatingOptIn> {
    opt_ins
        .iter()
        .find(|opt_in| opt_in.user_id == user_id)
        .ok_or_else(|| anyhow!("intentional dating opt-in not found for notification context"))
}

fn opt_in_display_name(opt_in: &IntentionalDatingOptIn) -> String {
    opt_in.name.clone().unwrap_or_else(|| opt_in.username.clone())
}
