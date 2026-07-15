//! HTTP handlers for the global site stats page.

use anyhow::Result;
use askama::Template;
use axum::{
    extract::State,
    http::{Uri, header::CACHE_CONTROL},
    response::{Html, IntoResponse},
};
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::{DynDB, common::SearchGroupsOutput},
    handlers::error::HandlerError,
    router::CACHE_CONTROL_PRIVATE_NO_STORE,
    templates::{
        PageId,
        auth::User,
        site::{
            explore::{self, render_group_popover},
            stats,
        },
    },
    types::search::{SearchGroupsFilters, ViewMode},
};

#[cfg(test)]
mod tests;

// Page handlers.

/// Handler that renders the global site stats page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    uri: Uri,
) -> Result<impl IntoResponse, HandlerError> {
    // Prepare template
    let (site_settings, stats, group_map) = tokio::try_join!(
        db.get_site_settings(),
        db.get_site_stats(),
        prepare_group_map(&db)
    )?;
    let template = stats::Page {
        page_id: PageId::SiteStats,
        path: uri.path().to_string(),
        site_settings,
        stats,
        group_map_groups: group_map.0,
        group_map_bbox: group_map.1,
        user: User::from_session(auth_session).await?,
    };

    Ok((
        [(CACHE_CONTROL, CACHE_CONTROL_PRIVATE_NO_STORE)],
        Html(template.render()?),
    ))
}

async fn prepare_group_map(
    db: &DynDB,
) -> Result<(Vec<explore::GroupCard>, Option<crate::db::BBox>)> {
    let filters = SearchGroupsFilters {
        alliance: vec!["goup".to_string()],
        include_bbox: Some(true),
        limit: Some(100),
        offset: Some(0),
        sort_by: Some("name".to_string()),
        view_mode: Some(ViewMode::Map),
        ..Default::default()
    };
    let SearchGroupsOutput {
        mut groups, bbox, ..
    } = db.search_groups(&filters).await?;

    for group in &mut groups {
        group.popover_html = Some(render_group_popover(group)?);
    }

    Ok((
        groups.into_iter().map(|group| explore::GroupCard { group }).collect(),
        bbox,
    ))
}
