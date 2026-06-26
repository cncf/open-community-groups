//! HTTP handlers for the public docs pages.

use askama::Template;
use axum::{
    extract::{Path, State},
    response::{Html, IntoResponse, Response},
};
use rust_embed::Embed;
use tracing::instrument;

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extend_public_shared_cache_headers},
    templates::{PageId, auth::User, site::docs::Page},
};

const DOCS_URL: &str = "/docs";
const INDEX_DOC: &str = "index.md";

#[derive(Embed)]
#[folder = "../docs"]
struct DocsAsset;

/// Render the docs index page.
#[instrument(skip_all, err)]
pub(crate) async fn index(
    auth_session: AuthSession,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    render_doc(auth_session, db, INDEX_DOC.to_string()).await
}

/// Render a nested docs page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
    Path(doc_path): Path<String>,
) -> Result<impl IntoResponse, HandlerError> {
    let Some(doc_path) = normalize_doc_path(&doc_path) else {
        return Err(HandlerError::NotFound);
    };
    render_doc(auth_session, db, doc_path).await
}

async fn render_doc(
    auth_session: AuthSession,
    db: DynDB,
    doc_path: String,
) -> Result<Response, HandlerError> {
    let Some(file) = DocsAsset::get(&doc_path) else {
        return Err(HandlerError::NotFound);
    };
    let markdown = std::str::from_utf8(file.data.as_ref())
        .map_err(|error| HandlerError::Other(anyhow::anyhow!(error)))?;
    let content_html = render_markdown(markdown, &doc_path);
    let path = if doc_path == INDEX_DOC {
        DOCS_URL.to_string()
    } else {
        format!("{DOCS_URL}/{doc_path}")
    };

    let template = Page {
        page_id: PageId::SiteDocs,
        path,
        site_settings: db.get_site_settings().await?,
        user: User::from_session(auth_session).await?,
        content_html,
    };

    Ok((
        extend_public_shared_cache_headers(&[])?,
        Html(template.render()?),
    )
        .into_response())
}

fn render_markdown(markdown: &str, doc_path: &str) -> String {
    let html = markdown::to_html_with_options(markdown, &markdown::Options::gfm())
        .unwrap_or_else(|_| "Unable to render docs.".to_string());
    rewrite_relative_doc_links(&html, doc_path)
}

fn normalize_doc_path(raw_path: &str) -> Option<String> {
    let mut path = raw_path.trim_start_matches('/').trim().to_string();
    if path.is_empty() {
        return Some(INDEX_DOC.to_string());
    }
    if path.contains('\\') || path.split('/').any(|part| matches!(part, "" | "." | "..")) {
        return None;
    }
    if path.ends_with('/') {
        path.push_str(INDEX_DOC);
    } else if !path.contains('.') {
        path.push_str(".md");
    }
    path.ends_with(".md").then_some(path)
}

fn rewrite_relative_doc_links(html: &str, doc_path: &str) -> String {
    let mut output = String::with_capacity(html.len());
    let mut remaining = html;
    while let Some(index) = remaining.find("href=\"") {
        let (before, after_before) = remaining.split_at(index + 6);
        output.push_str(before);
        let Some(end_quote) = after_before.find('"') else {
            output.push_str(after_before);
            return output;
        };
        let (href, after_href) = after_before.split_at(end_quote);
        output.push_str(&rewrite_href(href, doc_path));
        remaining = after_href;
    }
    output.push_str(remaining);
    output
}

fn rewrite_href(href: &str, doc_path: &str) -> String {
    if href.starts_with('#')
        || href.starts_with('/')
        || href.starts_with("http://")
        || href.starts_with("https://")
        || href.starts_with("mailto:")
        || href.starts_with("tel:")
    {
        return href.to_string();
    }

    let (href_path, fragment) = href
        .split_once('#')
        .map_or((href, ""), |(path, fragment)| (path, fragment));
    let base = doc_path.rsplit_once('/').map_or("", |(base, _)| base);
    let combined = if base.is_empty() {
        href_path.to_string()
    } else {
        format!("{base}/{href_path}")
    };
    let normalized = normalize_relative_path(&combined);
    if fragment.is_empty() {
        format!("{DOCS_URL}/{normalized}")
    } else {
        format!("{DOCS_URL}/{normalized}#{fragment}")
    }
}

fn normalize_relative_path(path: &str) -> String {
    let mut parts = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            _ => parts.push(part),
        }
    }
    parts.join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_doc_path() {
        assert_eq!(normalize_doc_path(""), Some("index.md".to_string()));
        assert_eq!(
            normalize_doc_path("guides/group-leads-runbook"),
            Some("guides/group-leads-runbook.md".to_string())
        );
        assert_eq!(normalize_doc_path("../secret"), None);
        assert_eq!(normalize_doc_path("guides/../secret"), None);
    }

    #[test]
    fn test_rewrite_relative_doc_links() {
        assert_eq!(
            rewrite_href("guides/group-leads-runbook.md", INDEX_DOC),
            "/docs/guides/group-leads-runbook.md"
        );
        assert_eq!(
            rewrite_href("../support/faq.md#help", "guides/group-leads-runbook.md"),
            "/docs/support/faq.md#help"
        );
        assert_eq!(
            rewrite_href("/dashboard/user", INDEX_DOC),
            "/dashboard/user"
        );
        assert_eq!(
            rewrite_href("https://example.com/docs", INDEX_DOC),
            "https://example.com/docs"
        );
    }
}
