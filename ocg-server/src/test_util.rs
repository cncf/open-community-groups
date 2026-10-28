//! Test helpers that belong to no layer: byte fixtures, text normalization,
//! and polling.

use std::{io::Cursor, time::Duration};

use image::{DynamicImage, ImageFormat};
use tokio::time::{sleep, timeout};

/// Collapses whitespace runs so rendered text can be matched exactly.
pub(crate) fn normalize_whitespace(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Encodes a transparent PNG image with the given dimensions.
pub(crate) fn sample_png(width: u32, height: u32) -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(width, height)
        .write_to(&mut output, ImageFormat::Png)
        .unwrap();
    output.into_inner()
}

/// Polls `condition` until it holds, failing the test after five seconds.
pub(crate) async fn wait_until(condition: impl Fn() -> bool) {
    timeout(Duration::from_secs(5), async {
        while !condition() {
            sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("condition to hold within the wait budget");
}
