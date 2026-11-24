//! Database operations for redirect loading.

use std::collections::HashMap;

use anyhow::Result;
use deadpool_postgres::Pool;
use tracing::{instrument, trace, warn};

use crate::router::{CommunityRedirects, Redirects, is_valid_http_url, is_valid_redirect_path};

/// DB implementation backed by `PostgreSQL`.
pub(crate) struct PgDB {
    /// Connection pool for `PostgreSQL` clients.
    pool: Pool,
}

impl PgDB {
    /// Creates a new `PgDB` instance with the provided connection pool.
    pub(crate) fn new(pool: Pool) -> Self {
        Self { pool }
    }

    /// Loads all redirects keyed by community name and normalized legacy path.
    #[instrument(skip(self), err)]
    pub(crate) async fn load_redirects(&self) -> Result<Redirects> {
        trace!("db: load redirects");

        let db = self.pool.get().await?;

        // Load redirector communities with their optional legacy fallbacks
        let community_rows = db
            .query(
                "select community_name, base_legacy_url from list_redirect_communities()",
                &[],
            )
            .await?;

        // Load concrete path redirects for migrated groups and events
        let redirect_rows = db
            .query(
                "select community_name, legacy_path, new_path from list_redirects()",
                &[],
            )
            .await?;

        // Collect typed community and mapping rows before validating into the redirect map
        let mut communities = Vec::with_capacity(community_rows.len());
        for row in community_rows {
            communities.push(RedirectCommunityRow {
                community_name: row.try_get("community_name")?,

                base_legacy_url: row.try_get("base_legacy_url")?,
            });
        }

        let mut mappings = Vec::with_capacity(redirect_rows.len());
        for row in redirect_rows {
            mappings.push(RedirectMappingRow {
                community_name: row.try_get("community_name")?,
                legacy_path: row.try_get("legacy_path")?,
                new_path: row.try_get("new_path")?,
            });
        }

        Ok(build_redirects(communities, mappings))
    }
}

/// Community row returned by `list_redirect_communities()`.
struct RedirectCommunityRow {
    /// Community name.
    community_name: String,

    /// Optional base legacy URL for fallback redirects.
    base_legacy_url: Option<String>,
}

/// Redirect mapping row returned by `list_redirects()`.
struct RedirectMappingRow {
    /// Community name.
    community_name: String,
    /// Normalized legacy path.
    legacy_path: String,
    /// Canonical relative target path.
    new_path: String,
}

/// Builds the validated redirect map from loaded community and mapping rows.
fn build_redirects(
    communities: Vec<RedirectCommunityRow>,
    mappings: Vec<RedirectMappingRow>,
) -> Redirects {
    let mut redirects = HashMap::new();

    // Seed all known communities, ignoring invalid legacy fallback URLs
    for row in communities {
        let base_legacy_url = row.base_legacy_url.and_then(|url| {
            if is_valid_http_url(&url) {
                Some(url)
            } else {
                warn!(
                    community_name = %row.community_name,
                    "ignoring invalid base_legacy_url"
                );
                None
            }
        });

        redirects.insert(
            row.community_name,
            CommunityRedirects {
                redirects: HashMap::new(),

                base_legacy_url,
            },
        );
    }

    // Attach validated path mappings to their community redirect settings
    for row in mappings {
        if !is_valid_redirect_path(&row.new_path) {
            warn!(
                community_name = %row.community_name,
                legacy_path = %row.legacy_path,
                new_path = %row.new_path,
                "ignoring invalid redirect target path"
            );
            continue;
        }

        redirects
            .entry(row.community_name)
            .or_default()
            .redirects
            .insert(row.legacy_path, row.new_path);
    }

    redirects
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_redirects_ignores_invalid_base_legacy_urls() {
        // Setup communities with valid and invalid legacy URL schemes and formats
        let communities = vec![
            RedirectCommunityRow {
                community_name: "https-ok".to_string(),

                base_legacy_url: Some("https://legacy.example/".to_string()),
            },
            RedirectCommunityRow {
                community_name: "http-ok".to_string(),

                base_legacy_url: Some("http://legacy.example:8080".to_string()),
            },
            RedirectCommunityRow {
                community_name: "ipv6-padded-port-ok".to_string(),

                base_legacy_url: Some("http://[::1]:00443/".to_string()),
            },
            RedirectCommunityRow {
                community_name: "javascript-bad".to_string(),

                base_legacy_url: Some("javascript:alert(1)".to_string()),
            },
            RedirectCommunityRow {
                community_name: "ftp-bad".to_string(),

                base_legacy_url: Some("ftp://legacy.example".to_string()),
            },
            RedirectCommunityRow {
                community_name: "scheme-relative-bad".to_string(),

                base_legacy_url: Some("//legacy.example".to_string()),
            },
            RedirectCommunityRow {
                community_name: "relative-bad".to_string(),

                base_legacy_url: Some("/legacy".to_string()),
            },
            RedirectCommunityRow {
                community_name: "query-bad".to_string(),

                base_legacy_url: Some("https://legacy.example?foo=bar".to_string()),
            },
            RedirectCommunityRow {
                community_name: "fragment-bad".to_string(),

                base_legacy_url: Some("https://legacy.example#frag".to_string()),
            },
            RedirectCommunityRow {
                community_name: "malformed-port-bad".to_string(),

                base_legacy_url: Some("https://legacy.example:bad".to_string()),
            },
            RedirectCommunityRow {
                community_name: "overflow-port-bad".to_string(),

                base_legacy_url: Some("https://legacy.example:99999".to_string()),
            },
            RedirectCommunityRow {
                community_name: "invalid-ipv6-bad".to_string(),

                base_legacy_url: Some("https://[bad-ip]".to_string()),
            },
            RedirectCommunityRow {
                community_name: "userinfo-bad".to_string(),

                base_legacy_url: Some("https://user:pass@legacy.example".to_string()),
            },
        ];

        // Build the redirect map
        let redirects = build_redirects(communities, Vec::new());

        // Check valid http(s) URLs are kept and invalid ones are dropped
        assert_eq!(
            redirects["https-ok"].base_legacy_url.as_deref(),
            Some("https://legacy.example/")
        );
        assert_eq!(
            redirects["http-ok"].base_legacy_url.as_deref(),
            Some("http://legacy.example:8080")
        );
        assert_eq!(
            redirects["ipv6-padded-port-ok"].base_legacy_url.as_deref(),
            Some("http://[::1]:00443/")
        );
        assert_eq!(redirects["javascript-bad"].base_legacy_url, None);
        assert_eq!(redirects["ftp-bad"].base_legacy_url, None);
        assert_eq!(redirects["scheme-relative-bad"].base_legacy_url, None);
        assert_eq!(redirects["relative-bad"].base_legacy_url, None);
        assert_eq!(redirects["query-bad"].base_legacy_url, None);
        assert_eq!(redirects["fragment-bad"].base_legacy_url, None);
        assert_eq!(redirects["malformed-port-bad"].base_legacy_url, None);
        assert_eq!(redirects["overflow-port-bad"].base_legacy_url, None);
        assert_eq!(redirects["invalid-ipv6-bad"].base_legacy_url, None);
        assert_eq!(redirects["userinfo-bad"].base_legacy_url, None);
    }

    #[test]
    fn test_build_redirects_ignores_invalid_redirect_paths() {
        // Setup mappings with valid root-relative paths and unsafe or malformed targets
        let communities = vec![RedirectCommunityRow {
            community_name: "cncf".to_string(),

            base_legacy_url: None,
        }];
        let mappings = vec![
            RedirectMappingRow {
                community_name: "cncf".to_string(),
                legacy_path: "/valid-group".to_string(),
                new_path: "/cncf/group/valid".to_string(),
            },
            RedirectMappingRow {
                community_name: "cncf".to_string(),
                legacy_path: "/protocol-relative".to_string(),
                new_path: "//evil.example/phish".to_string(),
            },
            RedirectMappingRow {
                community_name: "cncf".to_string(),
                legacy_path: "/absolute-url".to_string(),
                new_path: "https://evil.example/phish".to_string(),
            },
            RedirectMappingRow {
                community_name: "cncf".to_string(),
                legacy_path: "/userinfo-injection".to_string(),
                new_path: "@evil.example/phish".to_string(),
            },
            RedirectMappingRow {
                community_name: "cncf".to_string(),
                legacy_path: "/missing-slash".to_string(),
                new_path: "cncf/group/valid".to_string(),
            },
            RedirectMappingRow {
                community_name: "cncf".to_string(),
                legacy_path: "/header-injection".to_string(),
                new_path: "/cncf\r\nX-Injected: 1".to_string(),
            },
            RedirectMappingRow {
                community_name: "cncf".to_string(),
                legacy_path: "/fragment-header-injection".to_string(),
                new_path: "/cncf#\r\nX-Injected: 1".to_string(),
            },
        ];

        // Build the redirect map
        let redirects = build_redirects(communities, mappings);

        // Check only the valid root-relative path is retained
        assert_eq!(
            redirects["cncf"].redirects,
            HashMap::from([("/valid-group".to_string(), "/cncf/group/valid".to_string())])
        );
    }
}
