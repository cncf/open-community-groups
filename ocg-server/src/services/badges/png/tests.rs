//! Bounded PNG baking and extraction tests.

use std::io::Cursor;

use image::{DynamicImage, ImageFormat};

use super::{
    BadgesManagerError, CREDENTIAL_KEYWORD, MAX_CREDENTIAL_SIZE, MAX_PNG_CHUNKS, MAX_PNG_SIZE,
    bake, extract,
};

#[test]
fn test_bake_and_extract_round_trip_replaces_existing_credential() {
    // Bake and extract one credential from source artwork
    let source = sample_png();
    let first = bake(&source, br#"{"id":"first"}"#).unwrap();
    assert_eq!(extract(&first).unwrap(), br#"{"id":"first"}"#);

    // Check re-baking transcodes the artwork and replaces the credential
    let replaced = bake(&first, br#"{"id":"second"}"#).unwrap();
    assert_eq!(extract(&replaced).unwrap(), br#"{"id":"second"}"#);
}

#[test]
fn test_bake_rejects_oversized_credential() {
    let credential = vec![b'a'; MAX_CREDENTIAL_SIZE + 1];
    assert!(matches!(
        bake(&sample_png(), &credential),
        Err(BadgesManagerError::PngLimitExceeded)
    ));
}

#[test]
fn test_bake_rejects_oversized_source() {
    let source = vec![0_u8; MAX_PNG_SIZE + 1];
    assert!(matches!(
        bake(&source, b"{}"),
        Err(BadgesManagerError::PngLimitExceeded)
    ));
}

#[test]
fn test_bake_rejects_undecodable_source() {
    assert!(matches!(
        bake(b"not an image", b"{}"),
        Err(BadgesManagerError::InvalidImage)
    ));
}

#[test]
fn test_bake_rejects_wrong_artwork_dimensions() {
    // Encode valid artwork outside the canonical badge dimensions
    let mut source = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(256, 256)
        .write_to(&mut source, ImageFormat::Png)
        .unwrap();

    // Check the wrong dimensions are rejected
    assert!(matches!(
        bake(&source.into_inner(), b"{}"),
        Err(BadgesManagerError::InvalidImage)
    ));
}

#[test]
fn test_extract_rejects_chunk_count_above_limit() {
    // Insert ancillary chunks beyond the bounded chunk budget
    let mut png = bake(&sample_png(), b"{}").unwrap();
    let filler = test_png_chunk(*b"zzZz", &[]);
    for _ in 0..MAX_PNG_CHUNKS {
        insert_chunk_before_iend(&mut png, &filler);
    }

    // Check the bounded parser fails closed
    assert!(matches!(
        extract(&png),
        Err(BadgesManagerError::PngLimitExceeded)
    ));
}

#[test]
fn test_extract_rejects_compressed_credential_chunk() {
    // Insert a credential chunk that uses compression flags
    let mut png = bake(&sample_png(), b"{}").unwrap();
    let chunk = credential_chunk([1, 0, 0, 0, 0], b"{}");
    insert_chunk_before_iend(&mut png, &chunk);

    // Check the unsupported chunk layout is rejected
    assert!(matches!(extract(&png), Err(BadgesManagerError::InvalidPng)));
}

#[test]
fn test_extract_rejects_corrupt_png() {
    // Flip one bit inside the baked credential artwork
    let mut png = bake(&sample_png(), b"{}").unwrap();
    let last = png.len() - 1;
    png[last] ^= 1;

    // Check the corrupt stream is rejected
    assert!(matches!(extract(&png), Err(BadgesManagerError::InvalidPng)));
}

#[test]
fn test_extract_rejects_duplicate_credential_chunks() {
    // Insert a second credential chunk into baked artwork
    let mut png = bake(&sample_png(), b"{}").unwrap();
    let chunk = credential_chunk([0, 0, 0, 0, 0], b"{}");
    insert_chunk_before_iend(&mut png, &chunk);

    // Check the ambiguous credential stream is rejected
    assert!(matches!(extract(&png), Err(BadgesManagerError::InvalidPng)));
}

#[test]
fn test_extract_rejects_missing_credential_chunk() {
    assert!(matches!(
        extract(&sample_png()),
        Err(BadgesManagerError::InvalidPng)
    ));
}

#[test]
fn test_extract_rejects_non_png_input() {
    assert!(matches!(
        extract(b"not a png"),
        Err(BadgesManagerError::InvalidPng)
    ));
}

#[test]
fn test_extract_rejects_trailing_data_after_terminator() {
    // Append one valid chunk after the stream terminator
    let mut png = bake(&sample_png(), b"{}").unwrap();
    png.extend_from_slice(&test_png_chunk(*b"zzZz", &[]));

    // Check data beyond the terminator is rejected
    assert!(matches!(extract(&png), Err(BadgesManagerError::InvalidPng)));
}

#[test]
fn test_extract_rejects_truncated_stream() {
    // Remove the stream terminator from baked artwork
    let mut png = bake(&sample_png(), b"{}").unwrap();
    png.truncate(png.len() - 12);

    // Check the unterminated stream is rejected
    assert!(matches!(extract(&png), Err(BadgesManagerError::InvalidPng)));
}

#[test]
fn test_extract_rejects_undecodable_terminated_stream() {
    // Assemble a terminated chunk stream that is not a decodable image
    let fake = [
        b"\x89PNG\r\n\x1a\n".as_slice(),
        credential_chunk([0, 0, 0, 0, 0], b"{}").as_slice(),
        test_png_chunk(*b"IEND", &[]).as_slice(),
    ]
    .concat();

    // Check the stream is rejected before credential extraction
    assert!(matches!(
        extract(&fake),
        Err(BadgesManagerError::InvalidPng)
    ));
}

// Helpers.

/// Encode one credential iTXt chunk with explicit flag bytes.
fn credential_chunk(flags: [u8; 5], payload: &[u8]) -> Vec<u8> {
    let mut data = CREDENTIAL_KEYWORD.to_vec();
    data.extend_from_slice(&flags);
    data.extend_from_slice(payload);
    test_png_chunk(*b"iTXt", &data)
}

/// Insert one encoded chunk immediately before the trailing IEND chunk.
fn insert_chunk_before_iend(png: &mut Vec<u8>, chunk: &[u8]) {
    let iend_offset = png.len() - 12;
    png.splice(iend_offset..iend_offset, chunk.iter().copied());
}

/// Encode valid 512×512 PNG artwork.
fn sample_png() -> Vec<u8> {
    let mut output = Cursor::new(Vec::new());
    DynamicImage::new_rgba8(512, 512)
        .write_to(&mut output, ImageFormat::Png)
        .unwrap();
    output.into_inner()
}

/// Encode one PNG chunk with a valid CRC for malformed-stream tests.
fn test_png_chunk(kind: [u8; 4], data: &[u8]) -> Vec<u8> {
    let mut chunk = Vec::with_capacity(data.len() + 12);
    chunk.extend_from_slice(&u32::try_from(data.len()).unwrap().to_be_bytes());
    chunk.extend_from_slice(&kind);
    chunk.extend_from_slice(data);
    let mut hasher = crc32fast::Hasher::new();
    hasher.update(&kind);
    hasher.update(data);
    chunk.extend_from_slice(&hasher.finalize().to_be_bytes());
    chunk
}
