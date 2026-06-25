//! HTTP handlers for alliance email template settings.

use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, SelectedAllianceId, ValidatedFormQs},
    },
    templates::dashboard::alliance::email_templates::{self, SiteOnboardingEmailTemplate},
    types::permissions::AlliancePermission,
};

/// Displays the editable email templates page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    CurrentUser(user): CurrentUser,
    SelectedAllianceId(alliance_id): SelectedAllianceId,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let (can_manage_settings, onboarding) = tokio::try_join!(
        db.user_has_alliance_permission(
            &alliance_id,
            &user.user_id,
            AlliancePermission::SettingsWrite,
        ),
        db.get_site_onboarding_email_template()
    )?;

    let template = email_templates::Page {
        can_manage_settings,
        onboarding,
    };

    Ok(Html(template.render()?))
}

/// Updates the editable onboarding email template.
#[instrument(skip_all, err)]
pub(crate) async fn update(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedFormQs(template): ValidatedFormQs<SiteOnboardingEmailTemplate>,
) -> Result<impl IntoResponse, HandlerError> {
    db.update_site_onboarding_email_template(user.user_id, &template)
        .await?;

    Ok((StatusCode::NO_CONTENT, [("HX-Trigger", "refresh-body")]).into_response())
}
