use crate::{
    test_util::{element_html_with, opening_tag_with},
    types::tests::sample_site_settings,
};

use super::*;

#[test]
fn test_verify_page_header_renders_logo_variants_for_configured_urls() {
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
                    true,
                ),
                (
                    r#"<span class="relative" data-site-logo="dark" data-theme-image="dark">"#,
                    dark_url,
                    true,
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
        // Render the verify page with the case logos and keep its header navigation
        let html = VerifyPage {
            path: "/badges/verify".into(),
            site_settings: SiteSettings {
                header_logo_dark_url: header_logo_dark_url.map(str::to_string),
                header_logo_url: header_logo_url.map(str::to_string),
                ..sample_site_settings()
            },
            error: None,
            verified: None,
        }
        .render()
        .unwrap();
        let nav = element_html_with(&html, r#"aria-label="Badge navigation""#);

        // Check each logo wrapper and its image source and loading mode
        for (wrapper, src, lazy) in &logos {
            let logo = element_html_with(nav, wrapper);
            let image = opening_tag_with(logo, &format!(r#"src="{src}""#));
            assert!(image.starts_with("<img"), "{label}: {src}");
            assert_eq!(image.contains(r#"loading="lazy""#), *lazy, "{label}: {src}");
        }

        // Check no other logo wrapper, image or lazy image renders
        assert_eq!(
            nav.matches("data-site-logo").count(),
            logos.len(),
            "{label}"
        );
        assert_eq!(
            nav.matches(r#"alt="Test Site logo""#).count(),
            logos.len(),
            "{label}"
        );
        assert_eq!(
            nav.matches(r#"loading="lazy""#).count(),
            logos.iter().filter(|(_, _, lazy)| *lazy).count(),
            "{label}"
        );

        // Check only the paired light and dark wrappers carry a theme image marker
        assert_eq!(
            nav.matches(r#"data-theme-image="light""#).count(),
            usize::from(header_logo_url.is_some() && header_logo_dark_url.is_some()),
            "{label}"
        );
        assert_eq!(
            nav.matches(r#"data-theme-image="dark""#).count(),
            usize::from(header_logo_url.is_some() && header_logo_dark_url.is_some()),
            "{label}"
        );

        // Check the dark URL needs the light URL and the title replaces a missing light logo
        assert_eq!(
            nav.contains(dark_url),
            header_logo_url.is_some() && header_logo_dark_url.is_some(),
            "{label}"
        );
        assert_eq!(
            nav.contains(">Test Site</span>"),
            header_logo_url.is_none(),
            "{label}"
        );
    }
}
