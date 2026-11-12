use std::{
    collections::{BTreeMap, BTreeSet},
    path::Path,
};

use askama::Template;
use serde_json::Value;

use crate::{
    templates::{
        PageId,
        auth::UserMenuState,
        brand_ramp::{AZURE_RAMP, DARK_SURFACE},
        community, site,
    },
    test_util::{element_html_with, opening_tag_with},
    types::{
        community::{CommunityFull, CommunityStats},
        site::SiteSettings,
        tests::sample_site_settings,
    },
};

#[test]
fn test_base_layout_emits_dark_primary_roles() {
    // Setup palette cases: (label, palette, expected fill)
    let cases = [
        ("empty palette", BTreeMap::new(), "#0079d2"),
        (
            "navy palette",
            BTreeMap::from([(500, "#1E3A8A".to_string())]),
            "#4365b9",
        ),
    ];

    for (label, palette, expected_fill) in cases {
        // Render the base layout with the case palette and keep its head
        let mut site_settings = sample_site_settings();
        site_settings.theme.palette = palette;
        let html = render_base_layout(site_settings);
        let head = &html[..html.find("</head>").unwrap()];

        // Check every dark role is emitted once
        for role in [
            "edge",
            "edge-soft",
            "fg",
            "fg-bright",
            "fg-brighter",
            "fill",
            "fill-deep",
            "tint",
            "tint-strong",
        ] {
            let name = format!("--ocg-primary-dark-{role}:");
            assert_eq!(head.matches(&name).count(), 1, "{label}: {name}");
        }

        // Check the fill carries the solved value
        assert!(
            head.contains(&format!("--ocg-primary-dark-fill: {expected_fill};")),
            "{label}: {expected_fill}"
        );
    }
}

#[test]
fn test_base_layout_emits_light_primary_ramp() {
    // Setup palette cases: (label, palette, verbatim shades)
    let cases = [
        ("empty palette", BTreeMap::new(), vec![]),
        (
            "partial palette with a non-standard key",
            BTreeMap::from([
                (50, "#eff6ff".to_string()),
                (900, "#1e3a8a".to_string()),
                (975, "#000000".to_string()),
            ]),
            vec![(50, "#eff6ff"), (900, "#1e3a8a")],
        ),
    ];

    for (label, palette, verbatim_shades) in cases {
        // Render the base layout with the case palette and keep its head
        let mut site_settings = sample_site_settings();
        site_settings.theme.palette = palette;
        let html = render_base_layout(site_settings);
        let head = &html[..html.find("</head>").unwrap()];

        // Check every standard shade is emitted once with its palette or azure value
        for (shade, azure) in AZURE_RAMP {
            let expected = verbatim_shades
                .iter()
                .find(|(key, _)| *key == shade)
                .map_or(azure, |&(_, value)| value);
            let name = format!("--ocg-primary-light-{shade}:");
            assert_eq!(head.matches(&name).count(), 1, "{label}: {name}");
            assert!(
                head.contains(&format!("{name} {expected};")),
                "{label}: {name} {expected}"
            );
        }
        assert_eq!(
            head.matches("--ocg-primary-light-500:").count(),
            1,
            "{label}"
        );

        // Check palette keys outside the standard shades are not emitted
        assert_eq!(
            head.matches("--ocg-primary-light-").count(),
            AZURE_RAMP.len(),
            "{label}"
        );
        assert!(!head.contains("--ocg-primary-light-975:"), "{label}");

        // Check the head sets neither the raw brand color nor numbered primary shades
        assert!(!head.contains("--ocg-primary:"), "{label}");
        assert!(!head.contains("--color-primary-"), "{label}");
    }
}

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
    // Render the base layout and locate the head landmarks
    let html = render_base_layout(sample_site_settings());
    let viewport_meta = html.find(r#"<meta name="viewport""#).unwrap();
    let critical_style = html[..html.find(r#"html[data-theme="dark"]"#).unwrap()]
        .rfind("<style>")
        .unwrap();
    let preferences_tag = "<script data-ocg-preferences>";
    let preferences = html.find(preferences_tag).unwrap();
    let refresh_cleanup = html[..html.find(r#""ocg_refresh""#).unwrap()]
        .rfind("<script")
        .unwrap();

    // Check the critical style paints only the dark screen canvas with the dark surface fallback
    let (critical_style_html, _) = html[critical_style..].split_once("</style>").unwrap();
    let critical_style_body = critical_style_html.strip_prefix("<style>").unwrap();
    assert_eq!(
        critical_style_body.split_whitespace().collect::<Vec<_>>().join(" "),
        format!(
            r#"@media screen {{ html[data-theme="dark"] {{ background-color: var(--color-surface, {DARK_SURFACE}); }} }}"#
        )
    );

    // Check the preferences initializer is emitted once and verbatim
    assert_eq!(html.matches(preferences_tag).count(), 1);
    let (preferences_html, _) = html[preferences..].split_once("</script>").unwrap();
    let preferences_body = preferences_html.strip_prefix(preferences_tag).unwrap();
    assert!(
        preferences_body
            .contains(include_str!("../../templates/common/scripts/preferences_init.js").trim())
    );

    // Check the refresh cleanup is a classic synchronous inline script
    assert!(html[refresh_cleanup..].starts_with("<script>"));

    // Check the single viewport meta, the critical style and the initializers keep their order
    assert_eq!(html.matches(r#"<meta name="viewport""#).count(), 1);
    assert!(viewport_meta < critical_style);
    assert!(critical_style < preferences);
    assert!(preferences < refresh_cleanup);

    // Check the preferences initializer precedes stylesheets and external scripts
    assert!(preferences < html.find(r#"<link rel="stylesheet""#).unwrap());
    assert!(preferences < html.find("<script src=").unwrap());

    // Check the refresh cleanup runs before HTMX records the history path
    assert!(refresh_cleanup < html.find(r#"<script src="/static/vendor/js/htmx."#).unwrap());

    // Check the import map precedes every module script
    assert!(
        html.find(r#"<script type="importmap">"#).unwrap()
            < html.find(r#"<script type="module""#).unwrap()
    );

    // Check the html start tag and the browser chrome stay the same for every viewer
    let html_start = &html[html.find("<html").unwrap()..];
    assert_eq!(
        &html_start[..=html_start.find('>').unwrap()],
        r#"<html lang="en" class="h-full min-h-screen">"#
    );
    assert!(!html.contains(r#"name="theme-color""#));

    // Check the viewport mode and color theme behavior modules are loaded
    assert!(html.contains(r#"src="/static/js/common/viewport-mode."#));
    assert!(html.contains(r#"src="/static/js/common/theme."#));
}

#[test]
fn test_community_page_breadcrumb_pairs_each_banner_with_its_dark_variant() {
    // Setup banner URLs
    let banner_url = "https://example.test/community-banner.png";
    let banner_dark_url = "https://example.test/community-banner-dark.png";
    let banner_mobile_url = "https://example.test/community-banner-mobile.png";
    let banner_mobile_dark_url = "https://example.test/community-banner-mobile-dark.png";

    // Setup cases: (label, desktop dark url, mobile dark url)
    let cases = [
        (
            "both dark banners",
            Some(banner_dark_url),
            Some(banner_mobile_dark_url),
        ),
        ("desktop dark banner only", Some(banner_dark_url), None),
        (
            "mobile dark banner only",
            None,
            Some(banner_mobile_dark_url),
        ),
        ("no dark banners", None, None),
    ];

    for (label, dark_url, mobile_dark_url) in cases {
        // Render the community page with the case banners and keep its breadcrumb
        let html = community::Page {
            base_url: "https://example.test".to_string(),
            community: CommunityFull {
                banner_mobile_url: banner_mobile_url.to_string(),
                banner_url: banner_url.to_string(),
                display_name: "Test Community".to_string(),
                name: "test-community".to_string(),

                banner_dark_url: dark_url.map(str::to_string),
                banner_mobile_dark_url: mobile_dark_url.map(str::to_string),
                ..Default::default()
            },
            page_id: PageId::Community,
            path: "/test-community".to_string(),
            recently_added_groups: vec![],
            site_settings: sample_site_settings(),
            stats: community::Stats {
                stats: CommunityStats::default(),
            },
            upcoming_in_person_events: vec![],
            upcoming_virtual_events: vec![],
            user: UserMenuState::default(),
        }
        .render()
        .unwrap();
        let breadcrumb = opening_tag_with(&html, "<breadcrumb-nav");

        // Check the light banners always render and each dark banner only when set
        assert!(
            breadcrumb.contains(&format!(r#" banner-url="{banner_url}""#)),
            "{label}"
        );
        assert!(
            breadcrumb.contains(&format!(r#" banner-mobile-url="{banner_mobile_url}""#)),
            "{label}"
        );
        assert_eq!(
            breadcrumb.contains(&format!(r#" banner-dark-url="{banner_dark_url}""#)),
            dark_url.is_some(),
            "{label}"
        );
        assert_eq!(
            breadcrumb.contains(&format!(
                r#" banner-mobile-dark-url="{banner_mobile_dark_url}""#
            )),
            mobile_dark_url.is_some(),
            "{label}"
        );
        assert_eq!(
            breadcrumb.matches("dark-url=").count(),
            usize::from(dark_url.is_some()) + usize::from(mobile_dark_url.is_some()),
            "{label}"
        );
    }
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
fn test_header_renders_logo_variants_for_configured_urls() {
    // Setup logo URLs
    let light_url = "https://example.com/header-logo.png";
    let dark_url = "https://example.com/header-logo-dark.png";

    // Setup logo cases: (label, light url, dark url, logos as (wrapper tag, src, lazy))
    let cases = [
        (
            "both logos",
            Some(light_url),
            Some(dark_url),
            vec![
                (
                    r#"<span class="relative" data-site-logo="light" data-theme-image="light">"#,
                    light_url,
                    false,
                ),
                (
                    r#"<span class="relative" data-site-logo="dark" data-theme-image="dark">"#,
                    dark_url,
                    false,
                ),
            ],
        ),
        (
            "light logo only",
            Some(light_url),
            None,
            vec![(
                r#"<span class="relative plate" data-site-logo="plated">"#,
                light_url,
                false,
            )],
        ),
        ("dark logo only", None, Some(dark_url), vec![]),
        ("no logo", None, None, vec![]),
    ];

    for (label, header_logo_url, header_logo_dark_url, logos) in cases {
        // Render the header for the case logos outside home and dashboards
        let html = site::not_found::Page {
            page_id: PageId::SiteNotFound,
            path: "/explore".into(),
            site_settings: SiteSettings {
                header_logo_dark_url: header_logo_dark_url.map(str::to_string),
                header_logo_url: header_logo_url.map(str::to_string),
                ..sample_site_settings()
            },
            user: UserMenuState::default(),
        }
        .render()
        .unwrap();
        let header = element_html_with(&html, r#"id="header""#);

        // Check each logo wrapper and its image source and loading mode
        for (wrapper, src, lazy) in &logos {
            let logo = element_html_with(header, wrapper);
            let image = opening_tag_with(logo, &format!(r#"src="{src}""#));
            assert!(image.starts_with("<img"), "{label}: {src}");
            assert_eq!(image.contains(r#"loading="lazy""#), *lazy, "{label}: {src}");
        }

        // Check no other logo wrapper, image or lazy image renders
        assert_eq!(
            header.matches("data-site-logo").count(),
            logos.len(),
            "{label}"
        );
        assert_eq!(
            header.matches(r#"alt="Test Site logo""#).count(),
            logos.len(),
            "{label}"
        );
        assert_eq!(
            header.matches(r#"loading="lazy""#).count(),
            logos.iter().filter(|(_, _, lazy)| *lazy).count(),
            "{label}"
        );

        // Check only the paired light and dark wrappers carry a theme image marker
        assert_eq!(
            header.matches(r#"data-theme-image="light""#).count(),
            usize::from(header_logo_url.is_some() && header_logo_dark_url.is_some()),
            "{label}"
        );
        assert_eq!(
            header.matches(r#"data-theme-image="dark""#).count(),
            usize::from(header_logo_url.is_some() && header_logo_dark_url.is_some()),
            "{label}"
        );

        // Check the dark URL renders only together with the light URL
        assert_eq!(
            header.contains(dark_url),
            header_logo_url.is_some() && header_logo_dark_url.is_some(),
            "{label}"
        );
    }
}

#[test]
fn test_header_shows_phone_title_only_without_logo_outside_home_and_dashboards() {
    // Setup logo URLs
    let light_url = "https://example.test/logo.svg";
    let dark_url = "https://example.test/logo-dark.svg";

    // Setup header cases: (path, light url, dark url, title shown)
    let cases = [
        ("/explore", None, None, true),
        ("/explore", None, Some(dark_url), true),
        ("/explore", Some(light_url), None, false),
        ("/explore", Some(light_url), Some(dark_url), false),
        ("/", None, None, false),
        ("/dashboard/group", None, None, false),
    ];

    for (path, header_logo_url, header_logo_dark_url, shown) in cases {
        // Render the header for the case path and logos
        let html = site::not_found::Page {
            page_id: PageId::SiteNotFound,
            path: path.into(),
            site_settings: SiteSettings {
                header_logo_dark_url: header_logo_dark_url.map(str::to_string),
                header_logo_url: header_logo_url.map(str::to_string),
                ..sample_site_settings()
            },
            user: UserMenuState::default(),
        }
        .render()
        .unwrap();

        // Check the phone title link follows the path and the light logo
        assert_eq!(
            html.contains(r#"aria-label="Go to Test Site homepage""#),
            shown,
            "path {path}, logo {header_logo_url:?}, dark logo {header_logo_dark_url:?}"
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
