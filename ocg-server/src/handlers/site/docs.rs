//! HTTP handlers for the public docs pages.

use askama::Template;
use axum::{
    extract::{Path, State},
    http::header::CONTENT_TYPE,
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
    if let Some(asset_path) = normalize_doc_asset_path(&doc_path) {
        return render_asset(&asset_path);
    }

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

fn render_asset(asset_path: &str) -> Result<Response, HandlerError> {
    let Some(file) = DocsAsset::get(asset_path) else {
        return Err(HandlerError::NotFound);
    };
    let Some(content_type) = docs_asset_content_type(asset_path) else {
        return Err(HandlerError::NotFound);
    };

    Ok((
        extend_public_shared_cache_headers(&[(CONTENT_TYPE.as_str(), content_type)])?,
        file.data.into_owned(),
    )
        .into_response())
}

fn render_markdown(markdown: &str, doc_path: &str) -> String {
    let markdown = strip_html_comments(markdown);
    let markdown = strip_missing_markdown_images(&markdown, doc_path);
    let html = markdown::to_html_with_options(&markdown, &markdown::Options::gfm())
        .unwrap_or_else(|_| "Unable to render docs.".to_string());
    rewrite_relative_doc_attributes(&html, doc_path)
}

fn strip_html_comments(markdown: &str) -> String {
    let mut output = String::with_capacity(markdown.len());
    let mut remaining = markdown;
    while let Some(start) = remaining.find("<!--") {
        let (before, after_start) = remaining.split_at(start);
        output.push_str(before);
        let Some(end) = after_start.find("-->") else {
            return output;
        };
        remaining = &after_start[end + 3..];
    }
    output.push_str(remaining);
    output
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
    std::path::Path::new(&path)
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("md"))
        .then_some(path)
}

fn normalize_doc_asset_path(raw_path: &str) -> Option<String> {
    let path = raw_path.trim_start_matches('/').trim();
    if path.is_empty()
        || path.contains('\\')
        || path.split('/').any(|part| matches!(part, "" | "." | ".."))
    {
        return None;
    }
    is_supported_docs_asset(path).then_some(path.to_string())
}

fn is_supported_docs_asset(path: &str) -> bool {
    std::path::Path::new(path)
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(
                extension.to_ascii_lowercase().as_str(),
                "gif" | "jpeg" | "jpg" | "png" | "svg" | "webp"
            )
        })
}

fn docs_asset_content_type(path: &str) -> Option<&'static str> {
    let extension = std::path::Path::new(path).extension()?.to_str()?.to_ascii_lowercase();
    match extension.as_str() {
        "gif" => Some("image/gif"),
        "jpeg" | "jpg" => Some("image/jpeg"),
        "png" => Some("image/png"),
        "svg" => Some("image/svg+xml"),
        "webp" => Some("image/webp"),
        _ => None,
    }
}

fn strip_missing_markdown_images(markdown: &str, doc_path: &str) -> String {
    let mut output = String::with_capacity(markdown.len());
    for line in markdown.lines() {
        if let Some(image_path) = markdown_image_path(line.trim())
            && is_relative_url(image_path)
        {
            let normalized = normalize_doc_relative_path(image_path, doc_path);
            if DocsAsset::get(&normalized).is_none() {
                continue;
            }
        }
        output.push_str(line);
        output.push('\n');
    }
    output
}

fn markdown_image_path(line: &str) -> Option<&str> {
    let after_start = line.strip_prefix("![")?;
    let (_, after_alt) = after_start.split_once("](")?;
    let (path, _) = after_alt.split_once(')')?;
    Some(path.split_whitespace().next().unwrap_or(path).trim_matches('"'))
}

fn rewrite_relative_doc_attributes(html: &str, doc_path: &str) -> String {
    rewrite_relative_doc_attribute(
        &rewrite_relative_doc_attribute(html, doc_path, "href"),
        doc_path,
        "src",
    )
}

fn rewrite_relative_doc_attribute(html: &str, doc_path: &str, attribute: &str) -> String {
    let mut output = String::with_capacity(html.len());
    let mut remaining = html;
    let needle = format!("{attribute}=\"");
    while let Some(index) = remaining.find(&needle) {
        let (before, after_before) = remaining.split_at(index + needle.len());
        output.push_str(before);
        let Some(end_quote) = after_before.find('"') else {
            output.push_str(after_before);
            return output;
        };
        let (value, after_value) = after_before.split_at(end_quote);
        output.push_str(&rewrite_doc_url(value, doc_path));
        remaining = after_value;
    }
    output.push_str(remaining);
    output
}

fn rewrite_doc_url(url: &str, doc_path: &str) -> String {
    if !is_relative_url(url) {
        return url.to_string();
    }

    let (url_path, fragment) = url
        .split_once('#')
        .map_or((url, ""), |(path, fragment)| (path, fragment));
    let normalized = normalize_doc_relative_path(url_path, doc_path);
    if fragment.is_empty() {
        format!("{DOCS_URL}/{normalized}")
    } else {
        format!("{DOCS_URL}/{normalized}#{fragment}")
    }
}

fn is_relative_url(url: &str) -> bool {
    !(url.starts_with('#')
        || url.starts_with('/')
        || url.starts_with("http://")
        || url.starts_with("https://")
        || url.starts_with("mailto:")
        || url.starts_with("tel:"))
}

fn normalize_doc_relative_path(path: &str, doc_path: &str) -> String {
    let base = doc_path.rsplit_once('/').map_or("", |(base, _)| base);
    let combined = if base.is_empty() {
        path.to_string()
    } else {
        format!("{base}/{path}")
    };
    normalize_relative_path(&combined)
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
        assert_eq!(
            normalize_doc_asset_path("images/logo.svg"),
            Some("images/logo.svg".to_string())
        );
        assert_eq!(normalize_doc_asset_path("screenshots/missing.txt"), None);
        assert_eq!(normalize_doc_path("../secret"), None);
        assert_eq!(normalize_doc_path("guides/../secret"), None);
    }

    #[test]
    fn test_rewrite_relative_doc_links() {
        assert_eq!(
            rewrite_doc_url("guides/group-leads-runbook.md", INDEX_DOC),
            "/docs/guides/group-leads-runbook.md"
        );
        assert_eq!(
            rewrite_doc_url("../support/faq.md#help", "guides/group-leads-runbook.md"),
            "/docs/support/faq.md#help"
        );
        assert_eq!(
            rewrite_doc_url("/dashboard/user", INDEX_DOC),
            "/dashboard/user"
        );
        assert_eq!(
            rewrite_doc_url("https://example.com/docs", INDEX_DOC),
            "https://example.com/docs"
        );
        assert_eq!(
            rewrite_relative_doc_attributes(
                r#"<a href="guides/public-site.md">Guide</a><img src="images/logo.svg">"#,
                INDEX_DOC
            ),
            r#"<a href="/docs/guides/public-site.md">Guide</a><img src="/docs/images/logo.svg">"#
        );
    }

    #[test]
    fn test_strip_html_comments() {
        assert_eq!(
            strip_html_comments("<!-- markdownlint-disable MD013 -->\n# Docs"),
            "\n# Docs"
        );
        assert_eq!(strip_html_comments("# Docs\n\nBody"), "# Docs\n\nBody");
    }

    #[test]
    fn test_strip_missing_markdown_images() {
        assert_eq!(
            strip_missing_markdown_images(
                "Before\n![Missing](screenshots/missing.png)\nAfter",
                INDEX_DOC
            ),
            "Before\nAfter\n"
        );
        assert_eq!(
            strip_missing_markdown_images("![Logo](images/logo.svg)", INDEX_DOC),
            "![Logo](images/logo.svg)\n"
        );
    }
}
