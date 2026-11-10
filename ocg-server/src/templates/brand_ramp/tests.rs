use std::collections::{BTreeMap, BTreeSet};

use cached::Cached;

use crate::types::site::Theme;

use super::{
    AZURE_RAMP, BrandRamp, DARK_CANVAS, DARK_RAISED, DARK_SURFACE, FG_MAX_CHROMA,
    MIN_NON_TEXT_CONTRAST, MIN_TEXT_CONTRAST, PrimaryRoles, SCAN_STEPS, SOLVE_DARK_ROLES,
    color::{Oklch, Srgb},
};

/// Azure anchor shade, the dark roles anchor without a parseable palette 500.
const AZURE_ANCHOR: &str = "#0094FF";

/// Token region holding the light palette constants.
const CONSTANTS_REGION: TokenRegion = TokenRegion {
    opener: ":root {",
    reason: "light palette constants",
};

/// Token region holding the dark block.
const DARK_REGION: TokenRegion = TokenRegion {
    opener: ":root { @variant dark {",
    reason: "dark palette and brand dark roles",
};

/// Dark role sources `common/base.html` emits as `--ocg-primary-dark-*`.
const DARK_ROLES: [&str; 9] = [
    "edge",
    "edge-soft",
    "fg",
    "fg-bright",
    "fg-brighter",
    "fill",
    "fill-deep",
    "tint",
    "tint-strong",
];

/// Token region holding the light-island scope rule.
const SCOPE_REGION: TokenRegion = TokenRegion {
    opener: ":where(.plate, .ink) {",
    reason: "light-island scope, re-declared from light sources",
};

/// Token region holding the `@theme static` block.
const THEME_REGION: TokenRegion = TokenRegion {
    opener: "@theme static {",
    reason: "color tokens with their light values",
};

/// Token region marked in the stylesheet source that holds a single declaration block.
struct TokenRegion {
    /// Block opener with collapsed whitespace, including any nested block opener.
    opener: &'static str,
    /// Reason in the region start marker.
    reason: &'static str,
}

#[test]
fn test_azure_ramp_matches_theme_static_fallbacks() {
    // Locate the @theme static block in the stylesheet source
    let css = include_str!("../../../static/css/styles.src.css");
    let block = token_block(css, &THEME_REGION);

    // Collect the numbered primary shades with their fallback literals
    let mut fallbacks: Vec<(u32, String)> =
        block.lines().filter_map(primary_shade_fallback).collect();
    fallbacks.sort();

    // Check the fallbacks match the azure ramp, ignoring case
    let expected: Vec<(u32, String)> = AZURE_RAMP
        .iter()
        .map(|&(shade, value)| (shade, value.to_lowercase()))
        .collect();
    assert_eq!(fallbacks, expected);
}

#[test]
fn test_brand_ramp_from_theme_builds_light_shades() {
    // Setup palette cases: (label, palette, expected light ramp)
    let full_palette = vec![
        (50, "#eff6ff"),
        (100, "#dbeafe"),
        (200, "#bfdbfe"),
        (300, "#93c5fd"),
        (400, "#60a5fa"),
        (500, "#3b82f6"),
        (600, "rgb(37 99 235)"),
        (700, "#1d4ed8"),
        (800, "#1e40af"),
        (900, "#1e3a8a"),
        (950, "#172554"),
    ];
    let cases = [
        ("empty palette", vec![], owned_shades(&AZURE_RAMP)),
        (
            "partial palette",
            vec![(50, "#eff6ff"), (900, "#1e3a8a")],
            azure_ramp_with(&[(50, "#eff6ff"), (900, "#1e3a8a")]),
        ),
        (
            "full palette with a non-hex value",
            full_palette.clone(),
            owned_shades(&full_palette),
        ),
        (
            "palette keys outside the standard shades",
            vec![(25, "#ffffff"), (500, "#123456"), (975, "#000000")],
            azure_ramp_with(&[(500, "#123456")]),
        ),
    ];

    for (label, palette, expected) in cases {
        // Build the ramp from a theme with the case palette
        let theme = Theme {
            palette: palette
                .into_iter()
                .map(|(shade, value)| (shade, value.to_string()))
                .collect::<BTreeMap<_, _>>(),
            primary_color: "#0066cc".to_string(),
        };
        let ramp = BrandRamp::from_theme(&theme);

        // Check every standard shade is emitted in order with its expected value
        assert_eq!(ramp.light, expected, "{label}");
    }
}

#[test]
fn test_brand_ramp_from_theme_caches_dark_roles() {
    // Setup a theme with an anchor no other test uses
    let anchor = "#5A3E9B";
    let theme = theme_with(&[(500, anchor)]);
    let uncached = PrimaryRoles::solve(Srgb::parse_hex(anchor).unwrap());

    // Build the ramp and check the cache stores the roles under the anchor's 8-bit value
    let first = BrandRamp::from_theme(&theme).dark;
    let stored = SOLVE_DARK_ROLES
        .write()
        .cache_get("#5a3e9b")
        .cloned()
        .expect("cached dark roles");
    assert_eq!(role_values(&stored), role_values(&uncached));

    // Build the ramp again and check both builds return the uncached roles
    let second = BrandRamp::from_theme(&theme).dark;
    assert_eq!(role_values(&first), role_values(&uncached));
    assert_eq!(role_values(&second), role_values(&uncached));
}

#[test]
fn test_brand_ramp_from_theme_solves_dark_roles() {
    // Setup palette cases: (label, palette, primary color, effective anchor)
    let cases = [
        ("empty palette", vec![], "#0066cc", AZURE_ANCHOR),
        ("e2e site shape", vec![], "#0EA5E9", AZURE_ANCHOR),
        ("navy", vec![(500, "#1E3A8A")], "#1E3A8A", "#1E3A8A"),
        ("yellow", vec![(500, "#FACC15")], "#FACC15", "#FACC15"),
        ("near-black", vec![(500, "#050505")], "#050505", "#050505"),
        ("near-white", vec![(500, "#FAFAFA")], "#FAFAFA", "#FAFAFA"),
        ("red", vec![(500, "#FF0000")], "#FF0000", "#FF0000"),
        ("green", vec![(500, "#16A34A")], "#16A34A", "#16A34A"),
        ("magenta", vec![(500, "#D62293")], "#D62293", "#D62293"),
        (
            "non-hex anchor shade",
            vec![(500, "banana")],
            "#ff0000",
            AZURE_ANCHOR,
        ),
        (
            "no anchor shade",
            vec![(50, "#fef2f2"), (900, "#7f1d1d")],
            "#dc2626",
            AZURE_ANCHOR,
        ),
    ];
    let azure = BrandRamp::from_theme(&theme_with(&[])).dark;

    for (label, palette, primary_color, anchor) in cases {
        // Solve the dark roles from the case palette
        let mut theme = theme_with(&palette);
        theme.primary_color = primary_color.to_string();
        let dark = BrandRamp::from_theme(&theme).dark;

        // Check every target on the emitted values
        assert_dark_targets(label, anchor, &dark);

        // Check themes without a parseable anchor shade solve the azure roles
        if anchor == AZURE_ANCHOR {
            assert_eq!(role_values(&dark), role_values(&azure), "{label}");
        }
    }

    // Check white on the azure anchor fails, so the azure fill moves
    assert_ne!(azure.fill, "#0094ff");
}

#[test]
fn test_dark_block_covers_every_remapped_token() {
    // Collect the declarations of every token block in the stylesheet source
    let css = include_str!("../../../static/css/styles.src.css");
    let constants = declarations(token_block(css, &CONSTANTS_REGION));
    let dark = declarations(token_block(css, &DARK_REGION));
    let scope = declarations(token_block(css, &SCOPE_REGION));
    let theme = declarations(token_block(css, &THEME_REGION));

    // Check color tokens are declared in the token blocks only
    let parsed = [&dark, &scope, &theme]
        .iter()
        .flat_map(|block| block.keys())
        .filter(|name| name.starts_with("--color-"))
        .count();
    assert!(parsed > 0);
    assert_eq!(color_declaration_count(css), parsed);

    // Check every light constant backs its @theme static, island and dark tokens
    assert!(!constants.is_empty());
    for name in constants.keys() {
        let shade = name
            .strip_prefix("--ocg-light-")
            .unwrap_or_else(|| panic!("unexpected constant {name}"));
        let token = format!("--color-{shade}");
        assert_eq!(
            theme.get(token.as_str()).copied(),
            Some(format!("var({name})").as_str()),
            "{token}"
        );
        assert!(scope.contains_key(token.as_str()), "{token}");
        assert!(dark.contains_key(token.as_str()), "{token}");
    }

    // Check every primary role is re-declared on islands and reads a dark role source
    for role in theme.keys().copied().filter(|name| is_primary_role(name)) {
        assert!(scope.contains_key(role), "{role}");
        let source = dark
            .get(role)
            .and_then(|value| value.strip_prefix("var(--ocg-primary-dark-")?.strip_suffix(')'));
        assert!(
            source.is_some_and(|source| DARK_ROLES.contains(&source)),
            "{role}"
        );
    }

    // Check the numbered primary ramp mirrors the light ramp
    for (index, (shade, _)) in AZURE_RAMP.iter().enumerate() {
        let (mirror, _) = AZURE_RAMP[AZURE_RAMP.len() - 1 - index];
        assert_eq!(
            dark.get(format!("--color-primary-{shade}").as_str()).copied(),
            Some(format!("var(--ocg-primary-light-{mirror})").as_str()),
            "primary-{shade}"
        );
    }

    // Check the semantic tokens and every other dark token are hex colors
    for token in [
        "canvas",
        "danger-fill",
        "danger-text",
        "plate-edge",
        "raised",
        "shade",
        "surface",
    ] {
        assert!(
            dark.contains_key(format!("--color-{token}").as_str()),
            "{token}"
        );
    }
    for (name, value) in &dark {
        let primary = is_primary_role(name)
            || name
                .strip_prefix("--color-primary-")
                .is_some_and(|shade| shade.parse::<u32>().is_ok());
        assert!(
            primary || Srgb::parse_hex(value).is_some(),
            "{name}: {value}"
        );
    }
}

#[test]
fn test_dark_constants_match_dark_block() {
    // Locate the dark block region in the stylesheet source
    let css = include_str!("../../../static/css/styles.src.css");
    let block = token_block(css, &DARK_REGION);

    // Check the solver backgrounds mirror the dark tokens
    assert!(block.contains(&format!("--color-canvas: {DARK_CANVAS};")));
    assert!(block.contains(&format!("--color-surface: {DARK_SURFACE};")));
    assert!(block.contains(&format!("--color-raised: {DARK_RAISED};")));
}

#[test]
fn test_dark_palette_meets_contrast_floors() {
    // Setup the dark token colors
    let css = include_str!("../../../static/css/styles.src.css");
    let dark = declarations(token_block(css, &DARK_REGION));
    let remapped = |name: &str| dark.contains_key(format!("--color-{name}").as_str());
    let color = |name: &str| {
        dark.get(format!("--color-{name}").as_str())
            .and_then(|value| Srgb::parse_hex(value))
            .unwrap_or_else(|| panic!("no hex --color-{name}"))
    };
    let check = |foreground: &str, background: &str, floor: f64| {
        let ratio = color(foreground).contrast(color(background));
        assert!(
            ratio >= floor,
            "{foreground} on {background} is {ratio:.2}:1, below {floor}:1"
        );
    };

    // Check muted and danger text on every dark background
    for background in ["canvas", "surface", "raised", "stone-50", "stone-100"] {
        for foreground in ["stone-400", "stone-500", "danger-text"] {
            check(foreground, background, 4.5);
        }
    }

    // Check body text shades on the surface
    for shade in [600, 700, 800, 900] {
        check(&format!("stone-{shade}"), "surface", 7.0);
    }

    // Check status text on the surface and its tints, where both shades are remapped
    for hue in ["amber", "emerald", "green", "orange", "red", "yellow"] {
        for (foreground, background) in [
            (format!("{hue}-700"), "surface".to_string()),
            (format!("{hue}-800"), format!("{hue}-100")),
            (format!("{hue}-900"), format!("{hue}-50")),
        ] {
            if remapped(&foreground) && remapped(&background) {
                check(&foreground, &background, 4.5);
            }
        }
    }

    // Check white text on the danger fill
    let ratio = Srgb::WHITE.contrast(color("danger-fill"));
    assert!(ratio >= 4.5, "white on danger-fill is {ratio:.2}:1");

    // Check raised stays dark enough for a fill to carry white text at 4.5:1 and
    // still stand 3:1 off raised, which needs Y(raised) below about 0.0278
    assert!(color("raised").relative_luminance() <= 0.027);
}

#[test]
fn test_dark_variant_applies_on_screen_only() {
    // Locate the dark custom variant in the stylesheet source
    let css = include_str!("../../../static/css/styles.src.css");
    let variant = block_body(css, "@custom-variant dark {");

    // Check every slot sits under a screen media query, so print keeps the light tokens
    let slots = variant.matches("@slot").count();
    assert!(slots > 0);
    assert_eq!(variant.matches("@media").count(), slots);
    assert_eq!(variant.matches("@media screen").count(), slots);
}

#[test]
fn test_from_theme_pins_azure_dark_roles() {
    // Setup role cases from the default theme: (role, solved value, expected value)
    let dark = BrandRamp::from_theme(&Theme::default()).dark;
    let cases = [
        ("edge", &dark.edge, "#0078d1"),
        ("edge_soft", &dark.edge_soft, "#043e6f"),
        ("fg", &dark.fg, "#1897ff"),
        ("fg_bright", &dark.fg_bright, "#50a8ff"),
        ("fg_brighter", &dark.fg_brighter, "#74b8ff"),
        ("fill", &dark.fill, "#0079d2"),
        ("fill_deep", &dark.fill_deep, "#006aba"),
        ("tint", &dark.tint, "#09253f"),
        ("tint_strong", &dark.tint_strong, "#142f4a"),
    ];

    for (role, value, expected) in cases {
        // Check the solved role matches the pinned azure value
        assert_eq!(value, expected, "azure {role}");
    }
}

#[test]
fn test_primary_roles_solve_meets_dark_floors_on_grid() {
    // Setup a deterministic grid of anchors across hue, lightness and chroma
    for hue_step in 0..18 {
        for lightness in [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 0.98] {
            for chroma in [0.0, 0.06, 0.15, 0.25] {
                let anchor = Oklch {
                    c: chroma,
                    h: f64::from(hue_step) * 20.0,
                    l: lightness,
                }
                .to_srgb_in_gamut()
                .to_hex();

                // Solve the dark roles from the anchor and check every floor
                let dark = PrimaryRoles::solve(Srgb::parse_hex(&anchor).unwrap());
                assert_dark_targets(&anchor, &anchor, &dark);
            }
        }
    }
}

#[test]
fn test_primary_roles_solve_picks_first_passing_scan_step() {
    for anchor in [AZURE_ANCHOR, "#1E3A8A", "#FACC15", "#111111", "#16A34A"] {
        // Solve the dark roles and setup the backgrounds they must clear
        let anchor_lch = Srgb::parse_hex(anchor).unwrap().to_oklch();
        let dark = PrimaryRoles::solve(Srgb::parse_hex(anchor).unwrap());
        let parse = |value: &str| Srgb::parse_hex(value).unwrap();
        let backgrounds = [
            parse(DARK_CANVAS),
            parse(DARK_SURFACE),
            parse(DARK_RAISED),
            parse(&dark.tint),
            parse(&dark.tint_strong),
        ];

        // Setup scan cases: (role, solved value, chroma cap, contrast floor)
        let cases = [
            ("fg", &dark.fg, FG_MAX_CHROMA, MIN_TEXT_CONTRAST),
            ("edge", &dark.edge, f64::INFINITY, MIN_NON_TEXT_CONTRAST),
        ];
        for (role, value, max_chroma, floor) in cases {
            // Find the first scan step from black that rounds to the solved value
            let step_color = |step: u32| {
                Oklch {
                    c: anchor_lch.c.min(max_chroma),
                    h: anchor_lch.h,
                    l: f64::from(step) / f64::from(SCAN_STEPS),
                }
                .to_srgb_in_gamut()
                .rounded()
            };
            let step = (0..=SCAN_STEPS)
                .find(|&step| step_color(step).to_hex() == *value)
                .unwrap_or_else(|| panic!("{anchor} {role}: {value} is off the scan grid"));

            // Check the previous step misses the floor on some background
            let previous = step_color(step - 1);
            assert!(
                backgrounds.iter().any(|bg| previous.contrast(*bg) < floor),
                "{anchor} {role}: {} also clears",
                previous.to_hex()
            );
        }
    }
}

#[test]
fn test_light_island_scope_mirrors_theme_static() {
    // Collect the declarations of the light, island and dark token blocks
    let css = include_str!("../../../static/css/styles.src.css");
    let dark = declarations(token_block(css, &DARK_REGION));
    let scope = declarations(token_block(css, &SCOPE_REGION));
    let theme = declarations(token_block(css, &THEME_REGION));

    // Check every island declaration repeats its light value
    assert!(!scope.is_empty());
    for (name, value) in &scope {
        assert_eq!(theme.get(name), Some(value), "{name}");
    }

    // Check islands re-declare every token the dark block overrides, except plate-edge
    let dark_names: BTreeSet<&str> = dark.keys().copied().collect();
    let mut island_names: BTreeSet<&str> = scope.keys().copied().collect();
    island_names.insert("--color-plate-edge");
    assert_eq!(dark_names, island_names);
}

// Helpers.

/// Asserts every dark role target on the emitted values.
fn assert_dark_targets(label: &str, anchor: &str, dark: &PrimaryRoles) {
    // Check every role is a lowercase six-digit hex color
    for value in role_values(dark) {
        let digits = value.strip_prefix('#').unwrap_or_default();
        assert!(
            digits.len() == 6 && digits.chars().all(|ch| matches!(ch, '0'..='9' | 'a'..='f')),
            "{label}: {value}"
        );
    }

    // Setup the emitted colors and the backgrounds they sit on
    let parse = |value: &str| Srgb::parse_hex(value).unwrap();
    let white = Srgb::WHITE;
    let (raised, surface) = (parse(DARK_RAISED), parse(DARK_SURFACE));
    let backgrounds = [
        parse(DARK_CANVAS),
        surface,
        raised,
        parse(&dark.tint),
        parse(&dark.tint_strong),
    ];
    let (fill, fill_deep) = (parse(&dark.fill), parse(&dark.fill_deep));

    // Check white text on the fills, and the fill against the dark surfaces
    assert!(
        white.contrast(fill) >= 4.5,
        "{label}: white on fill {}",
        dark.fill
    );
    assert!(
        white.contrast(fill_deep) >= 4.5,
        "{label}: white on fill_deep"
    );
    assert!(
        fill.contrast(raised) >= 3.0,
        "{label}: fill on raised {}",
        dark.fill
    );
    assert!(fill.contrast(surface) >= 3.0, "{label}: fill on surface");
    assert_ne!(dark.fill, dark.fill_deep, "{label}");

    // Check text and edges against every background
    for background in backgrounds {
        for (name, value) in [
            ("fg", &dark.fg),
            ("fg_bright", &dark.fg_bright),
            ("fg_brighter", &dark.fg_brighter),
        ] {
            assert!(
                parse(value).contrast(background) >= 4.5,
                "{label}: {name} {value}"
            );
        }
        assert!(
            parse(&dark.edge).contrast(background) >= 3.0,
            "{label}: edge {}",
            dark.edge
        );
    }

    // Check the fg family brightens in order
    let lightness = |value: &str| parse(value).to_oklch().l;
    assert!(lightness(&dark.fg) < lightness(&dark.fg_bright), "{label}");
    assert!(
        lightness(&dark.fg_bright) < lightness(&dark.fg_brighter),
        "{label}"
    );

    // Check chromatic roles keep the anchor hue
    let anchor_lch = parse(anchor).to_oklch();
    if anchor_lch.c > 0.03 {
        for value in role_values(dark) {
            let lch = parse(value).to_oklch();
            if lch.c > 0.03 {
                let drift = (lch.h - anchor_lch.h + 540.0).rem_euclid(360.0) - 180.0;
                assert!(drift.abs() <= 5.0, "{label}: {value} drifts {drift}");
            }
        }
    }
}

/// Returns the azure ramp with the given shades replaced.
fn azure_ramp_with(overrides: &[(u32, &str)]) -> Vec<(u32, String)> {
    AZURE_RAMP
        .iter()
        .map(|&(shade, azure)| {
            let value = overrides
                .iter()
                .find(|(key, _)| *key == shade)
                .map_or(azure, |&(_, value)| value);
            (shade, value.to_string())
        })
        .collect()
}

/// Returns the body of the block that starts with the given opening.
fn block_body<'a>(css: &'a str, opening: &str) -> &'a str {
    // Locate the block opening
    let start = css.find(opening).unwrap_or_else(|| panic!("block {opening}")) + opening.len();

    // Return the body up to the matching closing brace
    let mut depth = 1;
    for (offset, ch) in css[start..].char_indices() {
        match ch {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return &css[start..start + offset];
                }
            }
            _ => {}
        }
    }
    panic!("unterminated block {opening}");
}

/// Counts the `--color-*` custom property declarations anywhere in a text: a
/// name followed by a colon, unlike reads such as `var(--color-surface)`.
fn color_declaration_count(text: &str) -> usize {
    text.match_indices("--color-")
        .filter(|&(start, prefix)| {
            text[start + prefix.len()..]
                .trim_start_matches(|ch: char| ch.is_ascii_alphanumeric() || ch == '-')
                .trim_start()
                .starts_with(':')
        })
        .count()
}

/// Parses the single-line custom property declarations of a block into a map
/// from name to value, rejecting duplicate names.
fn declarations(block: &str) -> BTreeMap<&str, &str> {
    let mut declarations = BTreeMap::new();
    for line in block.lines() {
        // Keep only custom property declarations
        let Some((name, value)) =
            line.trim().strip_suffix(';').and_then(|line| line.split_once(':'))
        else {
            continue;
        };
        if !name.starts_with("--") {
            continue;
        }

        // Record the value, rejecting a name declared twice
        let previous = declarations.insert(name, value.trim());
        assert!(previous.is_none(), "duplicate declaration {name}");
    }
    declarations
}

/// Returns whether a token is a primary role: `--color-focus` or a
/// `--color-primary-*` name that is not a numbered shade.
fn is_primary_role(name: &str) -> bool {
    name == "--color-focus"
        || name
            .strip_prefix("--color-primary-")
            .is_some_and(|rest| rest.parse::<u32>().is_err())
}

/// Returns the shades with owned values.
fn owned_shades(shades: &[(u32, &str)]) -> Vec<(u32, String)> {
    shades
        .iter()
        .map(|&(shade, value)| (shade, value.to_string()))
        .collect()
}

/// Parses a numbered primary shade declaration into its shade and lowercase
/// fallback literal, skipping any other line.
fn primary_shade_fallback(line: &str) -> Option<(u32, String)> {
    // Keep only numbered primary shade declarations
    let (shade, value) = line.trim().strip_prefix("--color-primary-")?.split_once(':')?;
    let shade: u32 = shade.parse().ok()?;

    // Extract the fallback literal of the light ramp variable
    let fallback = value
        .split_once(';')
        .and_then(|(value, _)| {
            value
                .trim()
                .strip_prefix(&format!("var(--ocg-primary-light-{shade},"))?
                .strip_suffix(')')
        })
        .unwrap_or_else(|| panic!("unexpected primary shade declaration: {line}"));

    Some((shade, fallback.trim().to_lowercase()))
}

/// Returns the nine dark roles in field order.
fn role_values(dark: &PrimaryRoles) -> [&str; 9] {
    [
        &dark.edge,
        &dark.edge_soft,
        &dark.fg,
        &dark.fg_bright,
        &dark.fg_brighter,
        &dark.fill,
        &dark.fill_deep,
        &dark.tint,
        &dark.tint_strong,
    ]
}

/// Returns a theme with the given palette.
fn theme_with(palette: &[(u32, &str)]) -> Theme {
    Theme {
        palette: palette
            .iter()
            .map(|&(shade, value)| (shade, value.to_string()))
            .collect(),
        primary_color: "#0066cc".to_string(),
    }
}

/// Returns the text between the markers of a token region, checking it holds only the
/// region block, so every declaration in it belongs to the innermost opener.
fn token_block<'a>(css: &'a str, region: &TokenRegion) -> &'a str {
    // Locate the text between the start and end markers
    let (opener, reason) = (region.opener, region.reason);
    let marker = format!("/* theme-lint: tokens-start {reason} */");
    let start = css.find(&marker).unwrap_or_else(|| panic!("token region {reason}")) + marker.len();
    let end = css[start..]
        .find("/* theme-lint: tokens-end */")
        .unwrap_or_else(|| panic!("token region {reason} end"));
    let text = &css[start..start + end];

    // Check the openers and their closers enclose the text, with no other block inside
    let collapsed = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let closers = vec!["}"; opener.matches('{').count()].join(" ");
    let body = collapsed
        .strip_prefix(opener)
        .and_then(|rest| rest.strip_suffix(closers.as_str()))
        .unwrap_or_else(|| panic!("token region {reason} is not one {opener} block"));
    assert!(!body.contains(['{', '}']), "{reason}: nested block");
    text
}
