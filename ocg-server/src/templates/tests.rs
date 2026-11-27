use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
};

use askama::Template;
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::{
    router::CSP_SCRIPT_HASHES,
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
fn test_base_layout_disables_htmx_eval() {
    // Render the shared base layout
    let base_html = render_base_layout(sample_site_settings());

    // Check HTMX eval is explicitly disabled in the document head
    assert!(base_html.contains(r#"<meta name="htmx-config" content='{"allowEval":false}'>"#));
}

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

    // Check the preferences initializer is emitted once and verbatim (normalized to LF)
    assert_eq!(html.matches(preferences_tag).count(), 1);
    let (preferences_html, _) = html[preferences..].split_once("</script>").unwrap();
    let preferences_body = preferences_html.strip_prefix(preferences_tag).unwrap();
    let expected_preferences_source =
        include_str!("../../templates/common/scripts/preferences_init.js")
            .replace("\r\n", "\n")
            .replace('\r', "\n");
    let expected_preferences_body = expected_preferences_source
        .strip_suffix('\n')
        .unwrap_or(&expected_preferences_source);
    assert_eq!(preferences_body, expected_preferences_body);

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

    // Check EasyMDE and MapLibre assets are lazy-loaded rather than global in head
    assert!(!html.contains("/static/vendor/css/maplibre-gl."));
    assert!(!html.contains("/static/vendor/css/easymde."));
    assert!(!html.contains("/static/vendor/js/easymde."));

    // Check SweetAlert2 is deferred and precedes the module scripts
    let swal_tag = opening_tag_with(&html, r#"src="/static/vendor/js/sweetalert2."#);
    assert!(swal_tag.contains(" defer"));
    assert!(
        html.find(r#"src="/static/vendor/js/sweetalert2."#).unwrap()
            < html.find(r#"<script type="module""#).unwrap()
    );
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

#[test]
fn test_rendered_inline_scripts_match_build_time_csp_hashes() {
    // Check the inline-script extractor catches uppercase tags and data-type lookalikes
    let synthetic_scripts = extract_non_json_inline_scripts(concat!(
        r#"<SCRIPT>alert(1)</SCRIPT>"#,
        r#"<script data-type="application/json">alert(2)</script>"#,
        r#"<script type="application/json">{"ok":true}</script>"#,
        r#"<script type="module" src="/static/js/app.js"></script>"#,
    ));
    assert_eq!(synthetic_scripts, vec!["alert(1)", "alert(2)"]);

    // Render every standalone layout that emits inline scripts
    let base_html = render_base_layout(sample_site_settings());
    let too_many_requests_html = site::too_many_requests::Page {
        message: "Please wait a moment.".to_string(),
    }
    .render()
    .unwrap();

    // Collect hashes built at compile time
    let build_hashes: BTreeSet<&str> = CSP_SCRIPT_HASHES.split_whitespace().collect();
    assert_eq!(
        build_hashes.len(),
        3,
        "expected 2 inline scripts + importmap"
    );

    // Hash every non-JSON inline <script> emitted by the rendered layouts
    let mut rendered_hashes = BTreeSet::new();
    for (page, html) in [
        ("base.html", base_html.as_str()),
        (
            "too_many_requests/page.html",
            too_many_requests_html.as_str(),
        ),
    ] {
        let scripts = extract_non_json_inline_scripts(html);
        assert_ne!(scripts.len(), 0, "{page} should contain inline scripts");
        for body in scripts {
            let hash = format!(
                "'sha256-{}'",
                BASE64_STANDARD.encode(Sha256::digest(body.as_bytes()))
            );
            assert!(
                build_hashes.contains(hash.as_str()),
                "{page} emitted an inline script whose hash {hash} is not in OCG_CSP_SCRIPT_HASHES ({CSP_SCRIPT_HASHES})"
            );
            rendered_hashes.insert(hash);
        }
    }

    // Check every build-time hash corresponds to a rendered inline script
    let rendered_hash_refs: BTreeSet<&str> = rendered_hashes.iter().map(String::as_str).collect();
    assert_eq!(rendered_hash_refs, build_hashes);

    // Check no other template source defines a non-JSON inline <script>
    let templates_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("templates");
    let mut template_files = Vec::new();
    collect_html_files(&templates_dir, &mut template_files);
    let mut unexpected_inline_scripts = Vec::new();
    for file in template_files {
        let rel = file
            .strip_prefix(&templates_dir)
            .unwrap()
            .to_string_lossy()
            .replace('\\', "/");
        if matches!(
            rel.as_str(),
            "common/base.html" | "site/too_many_requests/page.html"
        ) {
            continue;
        }
        let content = fs::read_to_string(&file).unwrap();
        let count = extract_non_json_inline_scripts(&content).len();
        if count > 0 {
            unexpected_inline_scripts.push(format!("{rel} ({count})"));
        }
    }
    assert!(
        unexpected_inline_scripts.is_empty(),
        "found unhashed inline <script> tags outside hashed layouts: {}",
        unexpected_inline_scripts.join(", ")
    );
}

#[test]
fn test_templates_contain_no_htmx_eval_attributes() {
    // Check the attribute scanner handles UTF-8 prefixes, mixed case, unquoted values,
    // eval-bearing hx-vars/hx-request attributes, and attributes following Askama tags
    let synthetic = concat!(
        "<!-- … so hx-get=\"/ignored\" -->",
        "<tr {% if cond %}HX-Trigger=keydown[key=='Enter'] hx-vals=js:{a:1} ",
        "hx-request=\"js:timeout:500\" hx-vars=\"x:1\" data-hx-on:click=\"foo()\"></tr>",
    );
    let synthetic_violations = find_htmx_eval_violations("synthetic.html", synthetic);
    assert_eq!(synthetic_violations.len(), 5, "{synthetic_violations:?}");

    // Collect all template source files
    let templates_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("templates");
    let mut template_files = Vec::new();
    collect_html_files(&templates_dir, &mut template_files);
    assert_ne!(template_files.len(), 0);

    // Verify no template relies on HTMX eval features disabled by allowEval: false
    let mut violations = Vec::new();
    for file in template_files {
        let content = fs::read_to_string(&file).unwrap();
        let rel = file.strip_prefix(&templates_dir).unwrap().display().to_string();
        violations.extend(find_htmx_eval_violations(&rel, &content));
    }

    assert!(
        violations.is_empty(),
        "found HTMX attributes incompatible with allowEval: false:\n{}",
        violations.join("\n")
    );
}

// Helpers.

/// Recursively collects `.html` files under `dir`.
fn collect_html_files(dir: &Path, files: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            collect_html_files(&path, files);
        } else if path.extension().is_some_and(|ext| ext == "html") {
            files.push(path);
        }
    }
}

/// Extracts `(attribute_name, attribute_value)` pairs for `hx-*` and `data-hx-*` attributes.
fn extract_htmx_attributes(html: &str) -> Vec<(String, String)> {
    let bytes = html.as_bytes();
    let mut attrs = Vec::new();
    let mut index = 0;

    while index + 3 <= bytes.len() {
        // Scan case-insensitively for `hx-` at an attribute or Askama-tag boundary
        if !bytes[index..index + 3].eq_ignore_ascii_case(b"hx-") {
            index += 1;
            continue;
        }
        let start = index;
        let is_boundary = |byte: u8| byte.is_ascii_whitespace() || byte == b'}';
        let is_data_prefix = start >= 5
            && bytes[start - 5..start].eq_ignore_ascii_case(b"data-")
            && start.checked_sub(6).is_none_or(|i| is_boundary(bytes[i]));
        let is_attr_start =
            start.checked_sub(1).is_none_or(|i| is_boundary(bytes[i])) || is_data_prefix;
        if !is_attr_start {
            index = start + 3;
            continue;
        }

        // Read attribute name through `=`, whitespace, or tag close
        let mut cursor = start;
        while cursor < bytes.len()
            && !bytes[cursor].is_ascii_whitespace()
            && !matches!(bytes[cursor], b'=' | b'>' | b'/')
        {
            cursor += 1;
        }
        let name = String::from_utf8_lossy(&bytes[start..cursor]).to_ascii_lowercase();

        // Read optional quoted or unquoted attribute value
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        let mut value = String::new();
        if cursor < bytes.len() && bytes[cursor] == b'=' {
            cursor += 1;
            while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
                cursor += 1;
            }
            if cursor < bytes.len() && matches!(bytes[cursor], b'"' | b'\'') {
                let quote = bytes[cursor];
                cursor += 1;
                let value_start = cursor;
                while cursor < bytes.len() && bytes[cursor] != quote {
                    cursor += 1;
                }
                value = String::from_utf8_lossy(&bytes[value_start..cursor]).into_owned();
                if cursor < bytes.len() {
                    cursor += 1;
                }
            } else {
                let value_start = cursor;
                while cursor < bytes.len()
                    && !bytes[cursor].is_ascii_whitespace()
                    && !matches!(bytes[cursor], b'>' | b'/')
                {
                    cursor += 1;
                }
                value = String::from_utf8_lossy(&bytes[value_start..cursor]).into_owned();
            }
        }

        attrs.push((name, value));
        index = cursor;
    }

    attrs
}

/// Extracts inner contents of every inline `<script>` tag that is not `type="application/json"`.
fn extract_non_json_inline_scripts(html: &str) -> Vec<&str> {
    let bytes = html.as_bytes();
    let mut scripts = Vec::new();
    let mut index = 0;

    while index + 7 <= bytes.len() {
        // Match `<script` case-insensitively at a valid tag name boundary
        if !bytes[index..index + 7].eq_ignore_ascii_case(b"<script")
            || bytes
                .get(index + 7)
                .is_some_and(|b| !b.is_ascii_whitespace() && *b != b'>' && *b != b'/')
        {
            index += 1;
            continue;
        }
        let Some(tag_end_rel) = html[index..].find('>') else {
            break;
        };
        let open_tag = &html[index..=index + tag_end_rel];
        let body_start = index + tag_end_rel + 1;

        // Locate matching `</script>` case-insensitively
        let mut close_pos = None;
        let mut search = body_start;
        while search + 9 <= bytes.len() {
            if bytes[search..search + 9].eq_ignore_ascii_case(b"</script>") {
                close_pos = Some(search);
                break;
            }
            search += 1;
        }
        let Some(body_end) = close_pos else {
            break;
        };
        let body = &html[body_start..body_end];

        // Inspect exact `src` and `type` attributes at attribute boundaries
        let open_lower = open_tag.to_ascii_lowercase();
        let has_src = has_html_attribute(&open_lower, "src");
        let is_json_data = html_attribute_value(&open_lower, "type")
            .is_some_and(|value| value.trim() == "application/json");
        if !has_src && !is_json_data {
            scripts.push(body);
        }

        index = body_end + "</script>".len();
    }

    scripts
}

/// Returns whether a lowercased opening tag contains an attribute with the exact name `attr`.
fn has_html_attribute(open_tag_lower: &str, attr: &str) -> bool {
    let bytes = open_tag_lower.as_bytes();
    let needle = format!("{attr}=");
    open_tag_lower
        .match_indices(&needle)
        .any(|(idx, _)| idx > 0 && (bytes[idx - 1].is_ascii_whitespace() || bytes[idx - 1] == b'}'))
}

/// Reads the value of an exact attribute from a lowercased opening tag.
fn html_attribute_value<'a>(open_tag_lower: &'a str, attr: &str) -> Option<&'a str> {
    let bytes = open_tag_lower.as_bytes();
    let needle = format!("{attr}=");
    for (idx, _) in open_tag_lower.match_indices(&needle) {
        if idx == 0 || (!bytes[idx - 1].is_ascii_whitespace() && bytes[idx - 1] != b'}') {
            continue;
        }
        let mut cursor = idx + needle.len();
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if cursor < bytes.len() && matches!(bytes[cursor], b'"' | b'\'') {
            let quote = bytes[cursor];
            cursor += 1;
            let start = cursor;
            while cursor < bytes.len() && bytes[cursor] != quote {
                cursor += 1;
            }
            return Some(&open_tag_lower[start..cursor]);
        }
        let start = cursor;
        while cursor < bytes.len()
            && !bytes[cursor].is_ascii_whitespace()
            && !matches!(bytes[cursor], b'>' | b'/')
        {
            cursor += 1;
        }
        return Some(&open_tag_lower[start..cursor]);
    }
    None
}

/// Reports HTMX attributes in `content` that require `allowEval: true`.
fn find_htmx_eval_violations(label: &str, content: &str) -> Vec<String> {
    let mut violations = Vec::new();
    for (attr, value) in extract_htmx_attributes(content) {
        if attr == "hx-trigger" && value.contains('[') {
            violations.push(format!("{label}: hx-trigger eval filter ({value})"));
        } else if attr == "hx-on" || attr.starts_with("hx-on:") || attr.starts_with("hx-on-") {
            violations.push(format!("{label}: {attr} requires allowEval"));
        } else if attr == "hx-vars" {
            violations.push(format!("{label}: hx-vars requires allowEval"));
        } else if matches!(attr.as_str(), "hx-vals" | "hx-headers" | "hx-request") {
            let trimmed = value.trim_start();
            if trimmed.starts_with("js:") || trimmed.starts_with("javascript:") {
                violations.push(format!("{label}: {attr} js expression requires allowEval"));
            }
        }
    }
    violations
}

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
