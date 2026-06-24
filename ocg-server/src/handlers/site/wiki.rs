//! HTTP handlers for the public wiki page.

use std::{cmp::Reverse, time::Duration};

use askama::Template;
use axum::{
    extract::State,
    response::{Html, IntoResponse},
};
use cached::proc_macro::cached;
use chrono::{DateTime, NaiveDate, TimeZone, Utc};
use quick_xml::{Reader, events::Event};
use tracing::{debug, instrument};

use crate::{
    auth::AuthSession,
    db::DynDB,
    handlers::{error::HandlerError, extend_public_shared_cache_headers},
    templates::{
        PageId,
        auth::User,
        site::wiki::{Page, WikiLink, WikiSection, WikiSource},
    },
};

const WIKI_URL: &str = "/wiki";
const MAX_LINKS_PER_SECTION: usize = 24;
const MAX_LINKS_PER_SOURCE: usize = 4;

#[derive(Debug, Clone, Copy)]
struct FeedSource {
    label: &'static str,
    url: &'static str,
}

#[derive(Debug, Clone, Copy)]
struct SectionSource {
    id: &'static str,
    title: &'static str,
    summary_topic: &'static str,
    fallback_summary: &'static str,
    sources: &'static [FeedSource],
}

const AI_SOURCES: &[FeedSource] = &[
    FeedSource {
        label: "arXiv AI",
        url: "https://export.arxiv.org/rss/cs.AI",
    },
    FeedSource {
        label: "Google AI",
        url: "https://blog.google/technology/ai/rss/",
    },
    FeedSource {
        label: "Simon Willison Blog",
        url: "https://simonwillison.net/atom/everything/",
    },
    FeedSource {
        label: "Hugging Face Blog",
        url: "https://huggingface.co/blog/feed.xml",
    },
    FeedSource {
        label: "Latent Space",
        url: "https://www.latent.space/feed",
    },
    FeedSource {
        label: "Import AI",
        url: "https://importai.substack.com/feed",
    },
    FeedSource {
        label: "The Batch by DeepLearning.AI",
        url: "https://www.deeplearning.ai/the-batch/feed/",
    },
    FeedSource {
        label: "OpenAI",
        url: "https://openai.com/news/rss.xml",
    },
    FeedSource {
        label: "Anthropic News",
        url: "https://www.anthropic.com/news/rss.xml",
    },
    FeedSource {
        label: "InfoQ AI/ML",
        url: "https://feed.infoq.com/AI-ML-Data-Engineering",
    },
    FeedSource {
        label: "LlamaIndex Blog",
        url: "https://www.llamaindex.ai/blog/rss.xml",
    },
    FeedSource {
        label: "LangChain Blog",
        url: "https://blog.langchain.com/rss/",
    },
    FeedSource {
        label: "a16z AI",
        url: "https://a16z.news/feed",
    },
    FeedSource {
        label: "Papers with Code Trending",
        url: "https://paperswithcode.com/rss.xml",
    },
];

const OPEN_SOURCE_SOURCES: &[FeedSource] = &[
    FeedSource {
        label: "GitHub Blog",
        url: "https://github.blog/feed/",
    },
    FeedSource {
        label: "CNCF",
        url: "https://www.cncf.io/feed/",
    },
    FeedSource {
        label: "Hacker News Front Page RSS",
        url: "https://hnrss.org/frontpage",
    },
    FeedSource {
        label: "GitHub Trending RSS",
        url: "https://mshibanami.github.io/GitHubTrendingRSS/daily/all.xml",
    },
];

const ENTREPRENEURSHIP_SOURCES: &[FeedSource] = &[
    FeedSource {
        label: "Y Combinator Blog",
        url: "https://www.ycombinator.com/blog/rss.xml",
    },
    FeedSource {
        label: "TechCrunch Startups",
        url: "https://techcrunch.com/category/startups/feed/",
    },
    FeedSource {
        label: "Lenny's Newsletter",
        url: "https://www.lennysnewsletter.com/feed",
    },
    FeedSource {
        label: "Sequoia Capital Blog",
        url: "https://www.sequoiacap.com/feed/",
    },
    FeedSource {
        label: "Paul Graham Essays",
        url: "https://paulgraham.com/index.xml",
    },
];

const WIKI_SECTIONS: &[SectionSource] = &[
    SectionSource {
        id: "ai",
        title: "AI",
        summary_topic: "AI research, product launches, and applied machine learning",
        fallback_summary: "Latest AI research and product updates from leading research labs and technology publishers.",
        sources: AI_SOURCES,
    },
    SectionSource {
        id: "opensource",
        title: "Open Source",
        summary_topic: "open-source infrastructure, developer tools, and community projects",
        fallback_summary: "Open-source infrastructure and developer ecosystem updates from project and community sources.",
        sources: OPEN_SOURCE_SOURCES,
    },
    SectionSource {
        id: "entrepreneurship",
        title: "Entrepreneurship",
        summary_topic: "startup building, fundraising, product strategy, and founder lessons",
        fallback_summary: "Startup and founder reading from accelerators, investors, and operator-focused publications.",
        sources: ENTREPRENEURSHIP_SOURCES,
    },
];

/// Render the public wiki page.
#[instrument(skip_all, err)]
pub(crate) async fn page(
    auth_session: AuthSession,
    State(db): State<DynDB>,
) -> Result<impl IntoResponse, HandlerError> {
    let (site_settings, sections) = tokio::join!(db.get_site_settings(), load_wiki_sections());
    let template = Page {
        page_id: PageId::SiteWiki,
        path: WIKI_URL.to_string(),
        site_settings: site_settings?,
        user: User::from_session(auth_session).await?,
        sections,
    };

    Ok((
        extend_public_shared_cache_headers(&[])?,
        Html(template.render()?),
    ))
}

#[cached(time = 900)]
pub(crate) async fn load_wiki_sections() -> Vec<WikiSection> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(8))
        .user_agent("GOUP Wiki/1.0")
        .build()
        .unwrap_or_else(|_| reqwest::Client::new());

    let mut sections = Vec::with_capacity(WIKI_SECTIONS.len());
    for section in WIKI_SECTIONS {
        sections.push(load_section(&client, section).await);
    }

    sections
}

async fn load_section(client: &reqwest::Client, section: &SectionSource) -> WikiSection {
    let mut links = Vec::new();

    for source in section.sources {
        match fetch_source_links(client, source).await {
            Ok(mut source_links) => links.append(&mut source_links),
            Err(error) => debug!("failed to load wiki source {}: {error}", source.url),
        }
    }

    links.sort_by_key(|link| Reverse(link.published_at));
    links.truncate(MAX_LINKS_PER_SECTION);

    WikiSection {
        id: section.id.to_string(),
        title: section.title.to_string(),
        summary: section_summary(section, &links),
        sources: section
            .sources
            .iter()
            .map(|source| WikiSource {
                label: source.label.to_string(),
                url: source.url.to_string(),
            })
            .collect(),
        links,
    }
}

async fn fetch_source_links(
    client: &reqwest::Client,
    source: &FeedSource,
) -> anyhow::Result<Vec<WikiLink>> {
    let body = client
        .get(source.url)
        .send()
        .await?
        .error_for_status()?
        .text()
        .await?;
    Ok(parse_feed_links(&body, source.label)
        .into_iter()
        .take(MAX_LINKS_PER_SOURCE)
        .collect())
}

fn section_summary(section: &SectionSource, links: &[WikiLink]) -> String {
    if links.is_empty() {
        return section.fallback_summary.to_string();
    }

    let sources = links
        .iter()
        .map(|link| link.source.as_str())
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>()
        .join(", ");

    format!(
        "A live digest of {} pulled from {}. Start with the linked source articles and papers below.",
        section.summary_topic, sources
    )
}

#[allow(clippy::too_many_lines)]
fn parse_feed_links(feed: &str, source_label: &str) -> Vec<WikiLink> {
    let mut reader = Reader::from_str(feed);
    reader.config_mut().trim_text(true);

    let mut links = Vec::new();
    let mut in_item = false;
    let mut current_tag: Option<Vec<u8>> = None;
    let mut title = String::new();
    let mut link = String::new();
    let mut published_at = String::new();

    loop {
        match reader.read_event() {
            Ok(Event::Eof) | Err(_) => break,
            Ok(Event::Start(event)) => {
                let name = event.name().as_ref().to_vec();
                if tag_name_is(&name, b"item") || tag_name_is(&name, b"entry") {
                    in_item = true;
                    title.clear();
                    link.clear();
                    published_at.clear();
                } else if in_item && is_supported_item_tag(&name) {
                    if tag_name_is(&name, b"link")
                        && let Some(href) = event
                            .attributes()
                            .filter_map(Result::ok)
                            .find(|attr| attr.key.as_ref() == b"href")
                            .and_then(|attr| String::from_utf8(attr.value.into_owned()).ok())
                    {
                        link = href;
                    }
                    current_tag = Some(name);
                }
            }
            Ok(Event::Text(text)) => {
                if in_item
                    && let Some(tag) = current_tag.as_deref()
                    && let Ok(decoded) = text.decode()
                {
                    match tag {
                        tag if tag_name_is(tag, b"title") && title.is_empty() => {
                            title = decoded.into_owned();
                        }
                        tag if tag_name_is(tag, b"link") && link.is_empty() => {
                            link = decoded.into_owned();
                        }
                        tag if is_date_tag(tag) && published_at.is_empty() => {
                            published_at = decoded.into_owned();
                        }
                        _ => {}
                    }
                }
            }
            Ok(Event::CData(text)) => {
                if in_item
                    && let Some(tag) = current_tag.as_deref()
                    && let Ok(decoded) = text.decode()
                {
                    match tag {
                        tag if tag_name_is(tag, b"title") && title.is_empty() => {
                            title = decoded.into_owned();
                        }
                        tag if tag_name_is(tag, b"link") && link.is_empty() => {
                            link = decoded.into_owned();
                        }
                        tag if is_date_tag(tag) && published_at.is_empty() => {
                            published_at = decoded.into_owned();
                        }
                        _ => {}
                    }
                }
            }
            Ok(Event::End(event)) => {
                let name = event.name().as_ref().to_vec();
                if tag_name_is(&name, b"item") || tag_name_is(&name, b"entry") {
                    if !title.trim().is_empty() && !link.trim().is_empty() {
                        links.push(WikiLink {
                            title: title.trim().to_string(),
                            url: link.trim().to_string(),
                            source: source_label.to_string(),
                            published_at: parse_feed_date(published_at.trim()),
                        });
                    }
                    in_item = false;
                    current_tag = None;
                } else if current_tag.as_deref() == Some(name.as_slice()) {
                    current_tag = None;
                }
            }
            Ok(Event::Empty(event)) => {
                if in_item
                    && tag_name_is(event.name().as_ref(), b"link")
                    && link.is_empty()
                    && let Some(href) = event
                        .attributes()
                        .filter_map(Result::ok)
                        .find(|attr| attr.key.as_ref() == b"href")
                        .and_then(|attr| String::from_utf8(attr.value.into_owned()).ok())
                {
                    link = href;
                }
            }
            Ok(_) => {}
        }
    }

    links
}

fn is_supported_item_tag(name: &[u8]) -> bool {
    tag_name_is(name, b"title") || tag_name_is(name, b"link") || is_date_tag(name)
}

fn is_date_tag(name: &[u8]) -> bool {
    tag_name_is(name, b"pubDate")
        || tag_name_is(name, b"published")
        || tag_name_is(name, b"updated")
        || tag_name_is(name, b"date")
}

fn tag_name_is(name: &[u8], expected: &[u8]) -> bool {
    name == expected
        || name
            .rsplit(|byte| *byte == b':')
            .next()
            .is_some_and(|local_name| local_name == expected)
}

fn parse_feed_date(value: &str) -> Option<DateTime<Utc>> {
    if value.is_empty() {
        return None;
    }

    DateTime::parse_from_rfc2822(value)
        .or_else(|_| DateTime::parse_from_rfc3339(value))
        .map(|date| date.with_timezone(&Utc))
        .ok()
        .or_else(|| {
            NaiveDate::parse_from_str(value, "%Y-%m-%d")
                .ok()
                .and_then(|date| date.and_hms_opt(0, 0, 0))
                .map(|date| Utc.from_utc_datetime(&date))
        })
}
