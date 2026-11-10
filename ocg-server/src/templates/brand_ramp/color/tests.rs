use super::{Oklch, Srgb};

#[test]
fn test_oklch_to_srgb_in_gamut_keeps_colors_in_gamut() {
    let color = Srgb::parse_hex("#0094ff").unwrap().to_oklch();

    assert_eq!(color.to_srgb_in_gamut().to_hex(), "#0094ff");
}

#[test]
fn test_oklch_to_srgb_in_gamut_stays_in_range() {
    // Setup out-of-gamut colors across hues, plus the lightness extremes
    let mut colors: Vec<Oklch> = (0..36)
        .flat_map(|step| {
            let h = f64::from(step) * 10.0;
            [0.2, 0.5, 0.8].map(|l| Oklch { c: 0.4, h, l })
        })
        .collect();
    colors.push(Oklch {
        c: 0.3,
        h: 250.0,
        l: 0.0,
    });
    colors.push(Oklch {
        c: 0.3,
        h: 250.0,
        l: 1.0,
    });

    for color in colors {
        // Map the color into gamut
        let mapped = color.to_srgb_in_gamut();

        // Check every channel is in range and the hue and lightness hold
        assert!(mapped.in_gamut(), "{color:?} -> {mapped:?}");
        let lch = mapped.to_oklch();
        if color.l > 0.0 && color.l < 1.0 {
            assert!((lch.l - color.l).abs() < 1e-6, "{color:?} -> {lch:?}");
            assert!(lch.c <= color.c, "{color:?} -> {lch:?}");
            if lch.c > 0.01 {
                let drift = (lch.h - color.h + 540.0).rem_euclid(360.0) - 180.0;
                assert!(drift.abs() < 1e-3, "{color:?} -> {lch:?}");
            }
        }
    }
}

#[test]
fn test_srgb_contrast_matches_wcag_references() {
    // Setup color pairs: (first, second, expected contrast)
    let cases = [
        ("#ffffff", "#0094ff", 3.144),
        ("#ffffff", "#000000", 21.0),
        ("#ffffff", "#767676", 4.54),
        ("#0094ff", "#ffffff", 3.144),
        ("#123456", "#123456", 1.0),
    ];

    for (first, second, expected) in cases {
        // Measure the contrast of the pair
        let first_color = Srgb::parse_hex(first).unwrap();
        let second_color = Srgb::parse_hex(second).unwrap();
        let contrast = first_color.contrast(second_color);

        // Check it matches the reference
        assert!(
            (contrast - expected).abs() < 0.005,
            "{first} on {second}: {contrast}"
        );
    }
}

#[test]
fn test_srgb_parse_hex_accepts_short_and_long_forms() {
    // Setup valid inputs: (input, expected lowercase hex)
    let valid = [
        ("#0094ff", "#0094ff"),
        ("#0094FF", "#0094ff"),
        ("#AbCdEf", "#abcdef"),
        ("#fff", "#ffffff"),
        ("#F0A", "#ff00aa"),
        ("#000", "#000000"),
    ];
    for (input, expected) in valid {
        // Check the parsed color formats back to the expected hex
        let color = Srgb::parse_hex(input).unwrap_or_else(|| panic!("{input} parses"));
        assert_eq!(color.to_hex(), expected, "{input}");
    }

    // Check malformed inputs are rejected
    let invalid = [
        "",
        "#",
        "red",
        "#12",
        "#1234",
        "#gggggg",
        "#aabbccdd",
        "0094ff",
        "rgb(0 0 0)",
        "#+12",
    ];
    for input in invalid {
        assert_eq!(Srgb::parse_hex(input), None, "{input}");
    }
}

#[test]
fn test_srgb_to_oklch_matches_reference() {
    // Convert the azure anchor
    let lch = Srgb::parse_hex("#0094FF").unwrap().to_oklch();

    // Check it matches the published OKLCH coordinates
    assert!((lch.l - 0.658).abs() < 0.001, "{lch:?}");
    assert!((lch.c - 0.189).abs() < 0.001, "{lch:?}");
    assert!((lch.h - 250.5).abs() < 0.1, "{lch:?}");
}

#[test]
fn test_srgb_to_oklch_round_trips_within_one_step() {
    // Setup colors across the sRGB cube, including the corners
    let levels = [0u8, 17, 64, 128, 191, 238, 255];
    for r in levels {
        for g in levels {
            for b in levels {
                // Convert the color to OKLCH and back
                let hex = format!("#{r:02x}{g:02x}{b:02x}");
                let color = Srgb::parse_hex(&hex).unwrap();
                let back = color.to_oklch().to_srgb();

                // Check every channel lands within one 8-bit step
                for (before, after) in [(color.r, back.r), (color.g, back.g), (color.b, back.b)] {
                    assert!((before - after).abs() <= 1.0 / 255.0, "{hex}: {back:?}");
                }
                assert_eq!(back.to_hex(), hex);
            }
        }
    }
}
