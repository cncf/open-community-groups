use std::io::Cursor;

use image::{DynamicImage, ImageFormat};

use crate::{
    services::images::MAX_IMAGE_SIZE_BYTES,
    test_util::sample_png,
    types::images::{Image, ImageTarget},
};

use super::{
    ImageValidationError, ValidatedImage, is_svg, validate_badge_artwork,
    validate_image_dimensions, validate_image_upload,
};

/// Message returned for any badge artwork that fails validation.
const INVALID_ARTWORK_MESSAGE: &str = "badge artwork must be a 512x512 PNG, JPEG, or WebP image";

/// SVG document free of scripts, handlers, and unsafe URLs.
const SAFE_SVG: &[u8] = br#"<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>"#;

#[test]
fn test_is_svg_accepts_safe_documents() {
    let cases: [(&str, &[u8]); 3] = [
        (
            "plain shapes",
            br#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
                <circle cx="50" cy="50" r="40" fill="blue"/>
            </svg>"#,
        ),
        (
            "image with a data image url",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <image href="data:image/png;base64,iVBORw0KGgoAAAANS=" />
            </svg>"#,
        ),
        (
            "multibyte attribute name",
            b"<svg xmlns=\"http://www.w3.org/2000/svg\"><circle a\xE2\x82\xAC=\"x\"/></svg>",
        ),
    ];
    for (case, svg) in cases {
        assert!(is_svg(svg, "svg"), "{case}");
    }
}

#[test]
#[allow(clippy::too_many_lines)]
fn test_is_svg_rejects_unsafe_documents() {
    let cases: [(&str, &[u8], &str); 20] = [
        (
            "data non-image url",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <image href="data:text/html,<script>alert('xss')</script>" />
            </svg>"#,
            "svg",
        ),
        (
            "data png url on a link",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <a href="data:image/png;base64,iVBORw0KGgoAAAANS=">click</a>
            </svg>"#,
            "svg",
        ),
        (
            "data svg image url",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <image href="data:image/svg+xml,&lt;svg onload='alert(1)'/&gt;" />
            </svg>"#,
            "svg",
        ),
        (
            "foreignObject element",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <foreignObject><body/></foreignObject>
            </svg>"#,
            "svg",
        ),
        (
            "javascript url behind a character reference",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <a href="jav&#x61;script:alert('xss')">click</a>
            </svg>"#,
            "svg",
        ),
        (
            "javascript url in href",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <a href="javascript:alert('xss')">click</a>
            </svg>"#,
            "svg",
        ),
        (
            "javascript url in xlink:href",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <image xlink:href="javascript:alert('xss')" />
            </svg>"#,
            "svg",
        ),
        (
            "javascript url split by whitespace",
            b"<svg xmlns=\"http://www.w3.org/2000/svg\">\n\
                <a href=\"java\x09script:alert('xss')\">click</a>\n\
            </svg>",
            "svg",
        ),
        (
            "malformed xml",
            b"<svg xmlns=\"http://www.w3.org/2000/svg\"><unclosed",
            "svg",
        ),
        (
            "missing namespace",
            b"<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>",
            "svg",
        ),
        (
            "namespaced event handler",
            br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
                <circle x:onload="alert('xss')" />
            </svg>"#,
            "svg",
        ),
        (
            "namespaced foreignObject element",
            br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
                <x:foreignObject><body/></x:foreignObject>
            </svg>"#,
            "svg",
        ),
        (
            "namespaced href",
            br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
                <a x:href="javascript:alert('xss')">click</a>
            </svg>"#,
            "svg",
        ),
        (
            "namespaced script element",
            br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
                <x:script>alert('xss')</x:script>
            </svg>"#,
            "svg",
        ),
        ("non-svg extension", SAFE_SVG, "png"),
        (
            "non-svg root element",
            br#"<html xmlns="http://www.w3.org/2000/svg"><body/></html>"#,
            "svg",
        ),
        (
            "non-utf-8 text",
            b"<svg xmlns=\"http://www.w3.org/2000/svg\"><text>caf\xE9</text></svg>",
            "svg",
        ),
        (
            "onclick attribute",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <circle onclick="alert('xss')" cx="50" cy="50" r="40"/>
            </svg>"#,
            "svg",
        ),
        (
            "onload attribute",
            br#"<svg xmlns="http://www.w3.org/2000/svg" onload="alert('xss')">
                <circle cx="50" cy="50" r="40"/>
            </svg>"#,
            "svg",
        ),
        (
            "script element",
            br#"<svg xmlns="http://www.w3.org/2000/svg">
                <script>alert('xss')</script>
            </svg>"#,
            "svg",
        ),
    ];
    for (case, svg, extension) in cases {
        assert!(!is_svg(svg, extension), "{case}");
    }
}

#[test]
fn test_validate_badge_artwork() {
    let mut oversized_png = sample_png(512, 512);
    oversized_png.resize(MAX_IMAGE_SIZE_BYTES + 1, 0);
    let cases = [
        ("512x512 png", "badge.png", png_image(512, 512), true),
        (
            "uppercase extension",
            "badge.PNG",
            png_image(512, 512),
            true,
        ),
        (
            "512x512 jpeg with jpg extension",
            "badge.jpg",
            encoded_image(ImageFormat::Jpeg, "image/jpeg"),
            true,
        ),
        (
            "512x512 jpeg with jpeg extension",
            "badge.jpeg",
            encoded_image(ImageFormat::Jpeg, "image/jpeg"),
            true,
        ),
        (
            "512x512 webp",
            "badge.webp",
            encoded_image(ImageFormat::WebP, "image/webp"),
            true,
        ),
        ("undersized png", "badge.png", png_image(1, 1), false),
        (
            "non-square png",
            "badge.png",
            stored_image(sample_png(512, 256), "image/png"),
            false,
        ),
        (
            "oversized png",
            "badge.png",
            stored_image(oversized_png, "image/png"),
            false,
        ),
        (
            "png bytes with jpg extension",
            "badge.jpg",
            png_image(512, 512),
            false,
        ),
        (
            "png bytes without extension",
            "badge",
            png_image(512, 512),
            false,
        ),
        (
            "png bytes with jpeg content type",
            "badge.png",
            stored_image(sample_png(512, 512), "image/jpeg"),
            false,
        ),
        (
            "unsupported gif format",
            "badge.gif",
            encoded_image(ImageFormat::Gif, "image/gif"),
            false,
        ),
        (
            "non-image bytes",
            "badge.png",
            stored_image(b"not an image".to_vec(), "image/png"),
            false,
        ),
    ];

    for (label, file_name, image, accepted) in cases {
        match validate_badge_artwork(file_name, &image) {
            Ok(()) => assert!(accepted, "{label}: should be rejected"),
            Err(err @ ImageValidationError::InvalidBadgeArtwork) => {
                assert!(!accepted, "{label}: should be accepted, got {err:?}");
                assert_eq!(err.to_string(), INVALID_ARTWORK_MESSAGE, "{label}");
            }
            Err(err) => panic!("{label}: unexpected error {err:?}"),
        }
    }
}

#[test]
fn test_validate_image_dimensions_requires_exact_target_size() {
    let cases = [
        (ImageTarget::AdBanner, "2400x300"),
        (ImageTarget::Badge, "512x512"),
        (ImageTarget::Banner, "2428x192"),
        (ImageTarget::BannerMobile, "1220x192"),
        (ImageTarget::Logo, "360x360"),
        (ImageTarget::OpenGraph, "1200x630"),
    ];
    for (target, size) in cases {
        // Check an exact-size image passes
        let exact = sample_png(target.width(), target.height());
        assert!(
            validate_image_dimensions(&exact, target).is_ok(),
            "{target:?} exact size"
        );

        // Check a 1x1 image is rejected with both sizes in the message
        assert_eq!(
            validate_image_dimensions(&sample_png(1, 1), target)
                .unwrap_err()
                .to_string(),
            format!("image dimensions 1x1 do not match required {size}"),
            "{target:?} wrong size"
        );
    }
}

#[test]
fn test_validate_image_upload_accepts_matching_images() {
    let cases = [
        (
            "exact-size badge png",
            "badge.png",
            sample_png(512, 512),
            Some(ImageTarget::Badge),
            ("image/png", "png"),
        ),
        (
            "svg logo skips the dimension check",
            "logo.svg",
            SAFE_SVG.to_vec(),
            Some(ImageTarget::Logo),
            ("image/svg+xml", "svg"),
        ),
        (
            "uppercase extension is lowercased",
            "A.PNG",
            sample_png(1, 1),
            None,
            ("image/png", "png"),
        ),
    ];
    for (case, file_name, bytes, target, (content_type, extension)) in cases {
        assert_eq!(
            validate_image_upload(file_name, &bytes, target).unwrap(),
            ValidatedImage {
                content_type,
                extension: extension.to_string(),
            },
            "{case}"
        );
    }
}

#[test]
fn test_validate_image_upload_rejects_invalid_images() {
    type IsExpectedError = fn(&ImageValidationError) -> bool;
    let extension_mismatch: IsExpectedError =
        |err| matches!(err, ImageValidationError::ExtensionMismatch);
    let public_format_required: IsExpectedError =
        |err| matches!(err, ImageValidationError::PublicFormatRequired { .. });
    let unsupported: IsExpectedError = |err| matches!(err, ImageValidationError::Unsupported(_));
    let cases = [
        (
            "png named as jpg",
            "image.jpg",
            sample_png(1, 1),
            None,
            extension_mismatch,
            "file extension does not match detected image format",
        ),
        (
            "png named without a dot",
            "image",
            sample_png(1, 1),
            None,
            extension_mismatch,
            "file extension does not match detected image format",
        ),
        (
            "svg badge",
            "badge.svg",
            SAFE_SVG.to_vec(),
            Some(ImageTarget::Badge),
            public_format_required,
            "Badge images must be PNG, JPEG, or WebP",
        ),
        (
            "svg open graph image",
            "og.svg",
            SAFE_SVG.to_vec(),
            Some(ImageTarget::OpenGraph),
            public_format_required,
            "Open Graph images must be PNG, JPEG, or WebP",
        ),
        (
            "empty extension",
            "image.",
            sample_png(1, 1),
            None,
            unsupported,
            "missing file extension",
        ),
        (
            "recognized but unsupported format",
            "image.bmp",
            b"BM\0\0\0\0\0\0\0\0\0\0\0\0".to_vec(),
            None,
            unsupported,
            "unsupported image format: Bmp",
        ),
        (
            "unsafe svg",
            "example.svg",
            br#"<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>"#.to_vec(),
            None,
            unsupported,
            "unsupported image format",
        ),
        (
            "unrecognized bytes",
            "image.png",
            b"not an image".to_vec(),
            None,
            unsupported,
            "unsupported image format",
        ),
        (
            "wrong dimensions",
            "logo.png",
            sample_png(1, 1),
            Some(ImageTarget::Logo),
            |err| matches!(err, ImageValidationError::Dimensions(_)),
            "image dimensions 1x1 do not match required 360x360",
        ),
    ];
    for (case, file_name, bytes, target, is_expected_error, message) in cases {
        let err = validate_image_upload(file_name, &bytes, target).unwrap_err();
        assert!(is_expected_error(&err), "{case}: {err:?}");
        assert_eq!(err.to_string(), message, "{case}");
    }
}

// Helpers.

/// Encodes a 512x512 test image in the requested raster format.
fn encoded_image(format: ImageFormat, content_type: &str) -> Image {
    let mut bytes = Vec::new();
    DynamicImage::new_rgb8(512, 512)
        .write_to(&mut Cursor::new(&mut bytes), format)
        .unwrap();
    stored_image(bytes, content_type)
}

/// Builds a stored PNG image with the requested dimensions.
fn png_image(width: u32, height: u32) -> Image {
    stored_image(sample_png(width, height), "image/png")
}

/// Builds a stored image fixture with the given bytes and content type.
fn stored_image(bytes: Vec<u8>, content_type: &str) -> Image {
    Image {
        bytes,
        content_type: content_type.to_string(),
    }
}
