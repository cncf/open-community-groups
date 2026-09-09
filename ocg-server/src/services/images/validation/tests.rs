use image::{ImageFormat, RgbaImage};

use super::{ImageTarget, is_svg, validate_image_dimensions};

const PNG_BYTES: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
];

#[test]
fn test_is_svg_accepts_valid_svg() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <circle cx="50" cy="50" r="40" fill="blue"/>
    </svg>"#;
    assert!(is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_accepts_valid_svg_with_data_image_url() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <image href="data:image/png;base64,iVBORw0KGgoAAAANS=" />
    </svg>"#;
    assert!(is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_data_non_image_url() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <image href="data:text/html,<script>alert('xss')</script>" />
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_data_png_url_on_link() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <a href="data:image/png;base64,iVBORw0KGgoAAAANS=">click</a>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_data_svg_image_url() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <image href="data:image/svg+xml,&lt;svg onload='alert(1)'/&gt;" />
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_foreign_object_element() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <foreignObject><body/></foreignObject>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_javascript_character_reference_url() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <a href="jav&#x61;script:alert('xss')">click</a>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_javascript_url_in_href() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <a href="javascript:alert('xss')">click</a>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_javascript_url_in_xlink_href() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <image xlink:href="javascript:alert('xss')" />
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_javascript_url_with_whitespace() {
    let svg = b"<svg xmlns=\"http://www.w3.org/2000/svg\">\n\
        <a href=\"java\x09script:alert('xss')\">click</a>\n\
    </svg>";
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_malformed_xml() {
    let malformed = b"<svg xmlns=\"http://www.w3.org/2000/svg\"><unclosed";
    assert!(!is_svg(malformed, "svg"));
}
#[test]
fn test_is_svg_rejects_missing_namespace() {
    let svg = b"<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>";
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_namespaced_event_handler() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
        <circle x:onload="alert('xss')" />
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_namespaced_foreign_object_element() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
        <x:foreignObject><body/></x:foreignObject>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_namespaced_href() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
        <a x:href="javascript:alert('xss')">click</a>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_namespaced_script_element() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:x="http://www.w3.org/2000/svg">
        <x:script>alert('xss')</x:script>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_non_svg_extension() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg"><circle/></svg>"#;
    assert!(!is_svg(svg, "png"));
}
#[test]
fn test_is_svg_rejects_non_svg_root_element() {
    let xml = br#"<html xmlns="http://www.w3.org/2000/svg"><body/></html>"#;
    assert!(!is_svg(xml, "svg"));
}
#[test]
fn test_is_svg_rejects_onclick_attribute() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <circle onclick="alert('xss')" cx="50" cy="50" r="40"/>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_onload_attribute() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" onload="alert('xss')">
        <circle cx="50" cy="50" r="40"/>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_is_svg_rejects_script_element() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg">
        <script>alert('xss')</script>
    </svg>"#;
    assert!(!is_svg(svg, "svg"));
}
#[test]
fn test_validate_badge_image_dimensions() {
    // Build an exact-size badge image
    let image = RgbaImage::new(512, 512);
    let mut bytes = Vec::new();
    image
        .write_to(&mut std::io::Cursor::new(&mut bytes), ImageFormat::Png)
        .unwrap();

    // Check exact badge dimensions pass and the 1x1 fixture fails
    assert!(validate_image_dimensions(&bytes, ImageTarget::Badge).is_ok());
    assert_eq!(
        validate_image_dimensions(PNG_BYTES, ImageTarget::Badge)
            .unwrap_err()
            .to_string(),
        "image dimensions 1x1 do not match required 512x512"
    );
}
#[test]
fn test_validate_image_dimensions_rejects_wrong_dimensions() {
    // PNG_BYTES is 1x1 pixel, should fail for any target
    let result = validate_image_dimensions(PNG_BYTES, ImageTarget::Logo);
    assert_eq!(
        result.unwrap_err().to_string(),
        "image dimensions 1x1 do not match required 360x360"
    );
}
