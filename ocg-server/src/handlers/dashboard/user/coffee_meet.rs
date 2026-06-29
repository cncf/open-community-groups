//! HTTP handlers for `CoffeeMeet` in the user dashboard.

use askama::Template;
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
};
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{
        error::HandlerError,
        extractors::{CurrentUser, ValidatedForm},
    },
    templates::dashboard::user::coffee_meet::{
        self, CoffeeMeetSubscriptionForm, CoffeeMeetUnsubscribeForm,
    },
};

/// Returns `CoffeeMeet` subscriptions for the current user.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let template = prepare_list_page(&db, user.user_id).await?;

    Ok(Html(template.render()?))
}

/// Subscribes or updates a `CoffeeMeet` cadence.
#[instrument(skip_all, err)]
pub(crate) async fn subscribe(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedForm(subscription): ValidatedForm<CoffeeMeetSubscriptionForm>,
) -> Result<impl IntoResponse, HandlerError> {
    db.upsert_coffee_meet_subscription(user.user_id, &subscription)
        .await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Unsubscribes from `CoffeeMeet` for a group.
#[instrument(skip_all, err)]
pub(crate) async fn unsubscribe(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    ValidatedForm(input): ValidatedForm<CoffeeMeetUnsubscribeForm>,
) -> Result<impl IntoResponse, HandlerError> {
    db.unsubscribe_coffee_meet(user.user_id, input.group_id).await?;

    Ok((
        StatusCode::NO_CONTENT,
        [("HX-Trigger", "refresh-user-dashboard-content")],
    ))
}

/// Prepares the `CoffeeMeet` subscriptions list page.
#[instrument(skip(db), err)]
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
) -> Result<coffee_meet::ListPage, HandlerError> {
    let subscriptions = db.list_user_coffee_meet_subscriptions(user_id).await?;

    Ok(coffee_meet::ListPage { subscriptions })
}
