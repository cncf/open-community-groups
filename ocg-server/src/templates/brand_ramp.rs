//! Brand color ramp for the base layout.
//!
//! `common/base.html` emits the ramp as `--ocg-primary-light-*` and
//! `--ocg-primary-dark-*` custom properties in its per-site `<style>` block.
//! The numbered primary shades in the `@theme static` block of
//! `styles.src.css` read the light shades, with the azure ramp as their
//! fallback, and the dark block reads the dark roles.

use cached::cached;

use crate::types::site::Theme;

use self::color::{Oklch, Srgb};

mod color;
#[cfg(test)]
mod tests;

/// Shade light mode paints on filled controls, which anchors the dark roles.
pub(crate) const ANCHOR_SHADE: u32 = 500;

/// Default azure primary ramp, from shade 50 to 950.
///
/// It mirrors the `@theme static` fallbacks in `styles.src.css`.
pub(crate) const AZURE_RAMP: [(u32, &str); 11] = [
    (50, "#EBF5FF"),
    (100, "#D6EBFF"),
    (200, "#ADD6FF"),
    (300, "#6BB8FF"),
    (400, "#29A3FF"),
    (500, "#0094FF"),
    (600, "#0077CC"),
    (700, "#005999"),
    (800, "#004880"),
    (900, "#003778"),
    (950, "#002152"),
];

/// Dark `canvas` color, mirroring the dark block in `styles.src.css`.
pub(crate) const DARK_CANVAS: &str = "#0b0a09";

/// Dark `raised` color, mirroring the dark block in `styles.src.css`.
pub(crate) const DARK_RAISED: &str = "#201d1b";

/// Dark `surface` color, mirroring the dark block in `styles.src.css`.
pub(crate) const DARK_SURFACE: &str = "#181514";

/// Highest chroma of `edge_soft`.
const EDGE_SOFT_MAX_CHROMA: f64 = 0.10;

/// Lightness step from `tint` up to `edge_soft`.
const EDGE_SOFT_STEP: f64 = 0.10;

/// Lightness step from `fg` up to `fg_brighter`.
const FG_BRIGHTER_STEP: f64 = 0.10;

/// Lightness step from `fg` up to `fg_bright`.
const FG_BRIGHT_STEP: f64 = 0.05;

/// Highest chroma of the `fg` family.
const FG_MAX_CHROMA: f64 = 0.20;

/// Lightness step from `fill` down to `fill_deep`.
const FILL_DEEP_STEP: f64 = 0.05;

/// Lowest contrast for edges, and for fills against the raised surface.
const MIN_NON_TEXT_CONTRAST: f64 = 3.0;

/// Lowest contrast for text.
const MIN_TEXT_CONTRAST: f64 = 4.5;

/// Lightness steps across the unit range in every scan, fine enough that
/// consecutive steps rarely skip an 8-bit value.
const SCAN_STEPS: u32 = 2048;

/// Highest chroma of `tint` and `tint_strong`.
const TINT_MAX_CHROMA: f64 = 0.06;

/// Lightness offset of `tint` above the dark surface.
const TINT_OFFSET: f64 = 0.06;

/// Lightness step from `tint` up to `tint_strong`.
const TINT_STRONG_STEP: f64 = 0.04;

/// Per-site brand color ramp rendered by the base layout.
#[derive(Debug, Clone)]
pub(crate) struct BrandRamp {
    /// Dark primary roles solved from the anchor shade.
    pub dark: PrimaryRoles,
    /// Light primary shades from 50 to 950, in order.
    pub light: Vec<(u32, String)>,
}

impl BrandRamp {
    /// Builds the brand ramp from the site theme.
    ///
    /// Each standard shade takes the palette value verbatim when present, even
    /// if it is not hex, and the azure literal otherwise. Palette keys outside
    /// the standard shades are read by no utility and are not emitted. The
    /// dark roles anchor on the palette's anchor shade when it parses, and on
    /// the azure one otherwise. `primary_color` is never read.
    pub(crate) fn from_theme(theme: &Theme) -> Self {
        // Take each light shade from the palette or the azure ramp
        let light = AZURE_RAMP
            .iter()
            .map(|&(shade, azure)| {
                let value = theme.palette.get(&shade).map_or(azure, String::as_str);
                (shade, value.to_string())
            })
            .collect();

        // Solve the dark roles from the effective anchor shade
        let anchor = theme
            .palette
            .get(&ANCHOR_SHADE)
            .and_then(|value| Srgb::parse_hex(value))
            .unwrap_or_else(azure_anchor);
        let dark = solve_dark_roles(anchor);

        Self { dark, light }
    }
}

/// Dark primary roles, each a lowercase `#rrggbb`.
#[derive(Debug, Clone)]
pub(crate) struct PrimaryRoles {
    /// Borders, rings, outlines and focus indicators, at least 3:1 on the dark
    /// backgrounds and tints.
    pub edge: String,
    /// Decorative borders, with no contrast floor.
    pub edge_soft: String,
    /// Text and icon marks, at least 4.5:1 on the dark backgrounds and tints.
    pub fg: String,
    /// Brighter text, one step above `fg`.
    pub fg_bright: String,
    /// Brightest text, two steps above `fg`.
    pub fg_brighter: String,
    /// Filled controls carrying white text, at least 3:1 on the raised surface.
    pub fill: String,
    /// Deeper filled controls carrying white text.
    pub fill_deep: String,
    /// Tinted backgrounds.
    pub tint: String,
    /// Stronger tinted backgrounds.
    pub tint_strong: String,
}

impl PrimaryRoles {
    /// Solves the dark roles from the anchor color.
    ///
    /// The tints and `edge_soft` sit at fixed lightness offsets above the dark
    /// surface. `fg` and `edge` are the darkest colors on the scan grid that
    /// clear their floor on every dark background, and `fg_bright` and
    /// `fg_brighter` step up from the lightness of the emitted `fg`. The anchor
    /// is kept as the fill when it carries white text and stands out from the
    /// raised surface. Otherwise the fill is darkened as little as possible
    /// until it carries white text, and then lightened as little as possible
    /// until it also stands out, keeping the darkened fill if no color does
    /// both. `fill_deep` is the lightest color carrying white text at least
    /// `FILL_DEEP_STEP` below the fill lightness.
    fn solve(anchor: Srgb) -> Self {
        // Setup the dark backgrounds and the anchor coordinates
        let canvas = parse_constant(DARK_CANVAS);
        let raised = parse_constant(DARK_RAISED);
        let surface = parse_constant(DARK_SURFACE);
        let anchor_lch = anchor.to_oklch();
        let at = |max_chroma: f64| {
            move |l: f64| Oklch {
                c: anchor_lch.c.min(max_chroma),
                h: anchor_lch.h,
                l,
            }
        };
        let anchor_color = at(f64::INFINITY);

        // Place the tints just above the surface
        let tint_l = surface.to_oklch().l + TINT_OFFSET;
        let tint = at(TINT_MAX_CHROMA)(tint_l).to_srgb_in_gamut().rounded();
        let tint_strong = at(TINT_MAX_CHROMA)(tint_l + TINT_STRONG_STEP)
            .to_srgb_in_gamut()
            .rounded();
        let edge_soft = at(EDGE_SOFT_MAX_CHROMA)(tint_l + EDGE_SOFT_STEP).to_srgb_in_gamut();

        // Find the darkest text colors that clear every background
        let backgrounds = [canvas, surface, raised, tint, tint_strong];
        let clears = |floor: f64| {
            move |color: Srgb| backgrounds.iter().all(|bg| color.contrast(*bg) >= floor)
        };
        let fg_color = at(FG_MAX_CHROMA);
        let (_, fg) = scan(0.0, 1.0, fg_color, clears(MIN_TEXT_CONTRAST))
            .expect("white clears every dark background");
        let fg_l = fg.to_oklch().l;
        let fg_bright = fg_color(fg_l + FG_BRIGHT_STEP).to_srgb_in_gamut().rounded();
        let fg_brighter = fg_color(fg_l + FG_BRIGHTER_STEP).to_srgb_in_gamut().rounded();

        // Find the darkest edge color that clears every background
        let (_, edge) = scan(0.0, 1.0, anchor_color, clears(MIN_NON_TEXT_CONTRAST))
            .expect("white clears every dark background");

        // Fit the fill between white text and the raised surface
        let carries_white = |color: Srgb| Srgb::WHITE.contrast(color) >= MIN_TEXT_CONTRAST;
        let stands_out = |color: Srgb| color.contrast(raised) >= MIN_NON_TEXT_CONTRAST;
        let (fill_l, fill) = if carries_white(anchor) && stands_out(anchor) {
            // Keep a brand that already fits
            (anchor_lch.l, anchor)
        } else {
            // Darken until white text fits
            let (darkened_l, darkened) = scan(anchor_lch.l, 0.0, anchor_color, carries_white)
                .expect("black carries white text");

            // Lighten until the fill stands out, keeping white text legible
            // over standing out if no color does both
            if stands_out(darkened) {
                (darkened_l, darkened)
            } else {
                scan(darkened_l, 1.0, anchor_color, |color| {
                    carries_white(color) && stands_out(color)
                })
                .unwrap_or((darkened_l, darkened))
            }
        };

        // Deepen the fill at the anchor chroma and hue
        let (_, fill_deep) = scan(fill_l - FILL_DEEP_STEP, 0.0, anchor_color, carries_white)
            .expect("black carries white text");

        Self {
            edge: edge.to_hex(),
            edge_soft: edge_soft.to_hex(),
            fg: fg.to_hex(),
            fg_bright: fg_bright.to_hex(),
            fg_brighter: fg_brighter.to_hex(),
            fill: fill.to_hex(),
            fill_deep: fill_deep.to_hex(),
            tint: tint.to_hex(),
            tint_strong: tint_strong.to_hex(),
        }
    }
}

/// Returns the azure anchor shade.
fn azure_anchor() -> Srgb {
    let (_, value) = AZURE_RAMP
        .iter()
        .find(|(shade, _)| *shade == ANCHOR_SHADE)
        .expect("azure ramp has the anchor shade");
    parse_constant(value)
}

/// Parses one of the color constants of this module.
fn parse_constant(value: &str) -> Srgb {
    Srgb::parse_hex(value).expect("valid color constant")
}

/// Steps lightness from `start` toward `end` and returns the first lightness
/// whose color, mapped into gamut and rounded to 8 bits, passes, together with
/// that rounded color.
///
/// Both ends are clamped to the unit range. Lightness moves `1 / SCAN_STEPS`
/// per step, starting at `start` itself and never going past `end`, so the
/// darkest or lightest passing color is so on that step grid.
fn scan(
    start: f64,
    end: f64,
    color: impl Fn(f64) -> Oklch,
    passes: impl Fn(Srgb) -> bool,
) -> Option<(f64, Srgb)> {
    let (start, end) = (start.clamp(0.0, 1.0), end.clamp(0.0, 1.0));
    let step = (end - start).signum() / f64::from(SCAN_STEPS);
    (0..=SCAN_STEPS)
        .map(|index| start + f64::from(index) * step)
        .take_while(|l| (start..=end).contains(l) || (end..=start).contains(l))
        .map(|l| (l, color(l).to_srgb_in_gamut().rounded()))
        .find(|&(_, rounded)| passes(rounded))
}

/// Solves the dark roles from the anchor color, memoized by its 8-bit value.
///
/// `common/base.html` builds the ramp on every render and the solve is pure,
/// so a small cache without expiry serves almost every render.
#[cached(max_size = 16, key = "String", convert = "{ anchor.to_hex() }")]
fn solve_dark_roles(anchor: Srgb) -> PrimaryRoles {
    PrimaryRoles::solve(anchor)
}
