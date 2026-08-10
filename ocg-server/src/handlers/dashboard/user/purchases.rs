//! HTTP handlers for attendee purchase document history.

use askama::Template;
use axum::{
    extract::{Path, RawQuery, State},
    http::HeaderName,
    response::{Html, IntoResponse, Redirect},
};
use garde::Validate;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::DynDB,
    handlers::{error::HandlerError, extractors::CurrentUser},
    router::serde_qs_config,
    services::payments::DynPaymentsManager,
    templates::dashboard::user::purchases,
    types::pagination::{self, NavigationLinks},
};

/// URL used by the full dashboard page.
const DASHBOARD_URL: &str = "/dashboard/user?tab=purchases";
/// URL used by the purchases tab partial.
const PARTIAL_URL: &str = "/dashboard/user/purchases";

/// Redirects an attendee to the provider's current credit-note URL.
#[instrument(skip_all, err)]
pub(crate) async fn credit_note_document(
    CurrentUser(user): CurrentUser,
    State(payments_manager): State<DynPaymentsManager>,
    Path((event_purchase_id, event_purchase_credit_note_id)): Path<(Uuid, Uuid)>,
) -> Result<Redirect, HandlerError> {
    purchase_document_redirect(
        &payments_manager,
        user.user_id,
        event_purchase_id,
        Some(event_purchase_credit_note_id),
    )
    .await
}

/// Redirects an attendee to the provider's current invoice URL.
#[instrument(skip_all, err)]
pub(crate) async fn invoice_document(
    CurrentUser(user): CurrentUser,
    State(payments_manager): State<DynPaymentsManager>,
    Path(event_purchase_id): Path<Uuid>,
) -> Result<Redirect, HandlerError> {
    purchase_document_redirect(&payments_manager, user.user_id, event_purchase_id, None).await
}

/// Returns the purchase-document list partial.
#[instrument(skip_all, err)]
pub(crate) async fn list_page(
    CurrentUser(user): CurrentUser,
    State(db): State<DynDB>,
    RawQuery(raw_query): RawQuery,
) -> Result<impl IntoResponse, HandlerError> {
    let (filters, template) =
        prepare_list_page(&db, user.user_id, raw_query.as_deref().unwrap_or_default()).await?;
    let url = pagination::build_url(DASHBOARD_URL, &filters)?;
    let headers = [(HeaderName::from_static("hx-push-url"), url)];

    Ok((headers, Html(template.render()?)))
}

/// Prepares purchase-document history for either the full page or tab partial.
pub(crate) async fn prepare_list_page(
    db: &DynDB,
    user_id: Uuid,
    raw_query: &str,
) -> Result<(purchases::PurchaseDocumentsFilters, purchases::ListPage), HandlerError> {
    let filters: purchases::PurchaseDocumentsFilters =
        serde_qs_config().deserialize_str(raw_query)?;
    filters.validate()?;
    let results = db.list_user_purchase_documents(user_id, &filters).await?;
    let navigation_links =
        NavigationLinks::from_filters(&filters, results.total, DASHBOARD_URL, PARTIAL_URL)?;

    Ok((
        filters.clone(),
        purchases::ListPage {
            limit: filters.limit,
            navigation_links,
            offset: filters.offset,
            purchases: results.purchases,
            total: results.total,
        },
    ))
}

/// Resolves attendee ownership before retrieving a fresh account-scoped URL.
async fn purchase_document_redirect(
    payments_manager: &DynPaymentsManager,
    user_id: Uuid,
    event_purchase_id: Uuid,
    event_purchase_credit_note_id: Option<Uuid>,
) -> Result<Redirect, HandlerError> {
    let url = payments_manager
        .get_purchase_document_url(user_id, event_purchase_id, event_purchase_credit_note_id)
        .await?
        .ok_or(HandlerError::NotFound)?;

    Ok(Redirect::temporary(&url))
}
