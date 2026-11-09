use std::{collections::BTreeSet, path::Path};

use askama::Template;
use serde_json::Value;

use crate::{
    templates::{PageId, auth::UserMenuState, site},
    test_util::element_html_with,
    types::{site::SiteSettings, tests::sample_site_settings},
};

#[test]
fn test_base_layout_import_map_points_lit_specifiers_to_one_vendored_bundle() {
    // Render the base layout and parse its import map
    let html = render_base_layout(sample_site_settings());
    let import_map_start = html.find(r#"<script type="importmap">"#).unwrap();
    let import_map_html = &html[import_map_start..];
    let import_map_json = &import_map_html
        [import_map_html.find('>').unwrap() + 1..import_map_html.find("</script>").unwrap()];
    let import_map: Value = serde_json::from_str(import_map_json).unwrap();
    let imports = import_map["imports"].as_object().unwrap();

    // Check only the supported Lit specifiers are mapped
    let specifiers: BTreeSet<&str> = imports.keys().map(String::as_str).collect();
    assert_eq!(
        specifiers,
        BTreeSet::from([
            "lit",
            "lit/directives/ref.js",
            "lit/directives/repeat.js",
            "lit/directives/unsafe-html.js",
        ])
    );

    // Check every specifier points to the same vendored Lit bundle
    let bundle_path = imports["lit"].as_str().unwrap();
    assert!(bundle_path.starts_with("/static/vendor/js/lit-all.v"));
    for (specifier, path) in imports {
        assert_eq!(path.as_str(), Some(bundle_path), "{specifier}");
    }

    // Check the vendored bundle exists in the static assets
    let bundle_file = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("static")
        .join(bundle_path.trim_start_matches("/static/"));
    assert!(bundle_file.exists(), "{}", bundle_file.display());
}

#[test]
fn test_base_layout_links_configured_or_default_favicon() {
    let cases = [
        (
            "default favicon",
            None,
            r#"href="/static/images/favicon.svg""#,
        ),
        (
            "configured favicon",
            Some("https://example.test/favicon.ico"),
            r#"<link rel="icon" href="https://example.test/favicon.ico""#,
        ),
    ];

    for (label, favicon_url, expected_link) in cases {
        // Render the base layout with the case favicon
        let html = render_base_layout(SiteSettings {
            favicon_url: favicon_url.map(str::to_string),
            ..sample_site_settings()
        });

        // Check the expected favicon link is the only one rendered
        assert!(html.contains(expected_link), "{label}");
        assert_eq!(html.matches(r#"<link rel="icon""#).count(), 1, "{label}");
        if favicon_url.is_some() {
            assert!(!html.contains("/static/images/favicon.svg"), "{label}");
        }
    }
}

#[test]
fn test_base_layout_runs_inline_initializers_before_assets() {
    // Render the base layout and locate both inline head scripts
    let html = render_base_layout(sample_site_settings());
    let viewport_mode_init = html[..html.find("ocg_viewport_mode=desktop").unwrap()]
        .rfind("<script")
        .unwrap();
    let refresh_cleanup = html[..html.find(r#""ocg_refresh""#).unwrap()]
        .rfind("<script")
        .unwrap();

    // Check both initializers are classic synchronous inline scripts
    assert!(html[viewport_mode_init..].starts_with("<script>"));
    assert!(html[refresh_cleanup..].starts_with("<script>"));

    // Check the single viewport meta precedes the viewport mode initializer
    assert_eq!(html.matches(r#"<meta name="viewport""#).count(), 1);
    assert!(html.find(r#"<meta name="viewport""#).unwrap() < viewport_mode_init);

    // Check the viewport mode initializer precedes stylesheets and external scripts
    assert!(viewport_mode_init < html.find(r#"<link rel="stylesheet""#).unwrap());
    assert!(viewport_mode_init < html.find("<script src=").unwrap());

    // Check the refresh cleanup runs before HTMX records the history path
    assert!(refresh_cleanup < html.find(r#"<script src="/static/vendor/js/htmx."#).unwrap());

    // Check the import map precedes every module script
    assert!(
        html.find(r#"<script type="importmap">"#).unwrap()
            < html.find(r#"<script type="module""#).unwrap()
    );

    // Check the viewport mode click behaviour module is loaded
    assert!(html.contains(r#"src="/static/js/common/viewport-mode."#));
}

#[test]
fn test_header_names_user_menu_placeholder() {
    // Render a page whose header defers the user menu
    let html = render_base_layout(sample_site_settings());

    // Check the loading placeholder button is named User menu
    let placeholder = element_html_with(&html, r#"hx-get="/section/user-menu""#);
    assert!(placeholder.contains(r#"aria-label="User menu""#));
}

#[test]
fn test_header_shows_phone_title_only_without_logo_outside_home_and_dashboards() {
    let cases = [
        ("/explore", None, true),
        ("/explore", Some("https://example.test/logo.svg"), false),
        ("/", None, false),
        ("/dashboard/group", None, false),
    ];

    for (path, header_logo_url, shown) in cases {
        // Render the header for the case path and logo
        let html = site::not_found::Page {
            page_id: PageId::SiteNotFound,
            path: path.into(),
            site_settings: SiteSettings {
                header_logo_url: header_logo_url.map(str::to_string),
                ..sample_site_settings()
            },
            user: UserMenuState::default(),
        }
        .render()
        .unwrap();

        // Check the phone title link follows the path and logo
        assert_eq!(
            html.contains(r#"aria-label="Go to Test Site homepage""#),
            shown,
            "path {path}, logo {header_logo_url:?}"
        );
    }
}

// Helpers.

/// Renders the shared base layout through the site not found page.
fn render_base_layout(site_settings: SiteSettings) -> String {
    site::not_found::Page {
        page_id: PageId::SiteNotFound,
        path: "/missing".into(),
        site_settings,
        user: UserMenuState::default(),
    }
    .render()
    .unwrap()
}
