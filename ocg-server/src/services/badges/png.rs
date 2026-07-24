//! Bounded Open Badges PNG baking and extraction.

use std::io::Cursor;

use crc32fast::Hasher;
use image::{GenericImageView, ImageFormat, ImageReader, Limits};

use super::{BadgeServiceError, Result};

const CREDENTIAL_KEYWORD: &[u8] = b"openbadgecredential";
const IEND: &[u8; 4] = b"IEND";
const ITXT: &[u8; 4] = b"iTXt";
pub(super) const MAX_CREDENTIAL_SIZE: usize = 256 * 1024;
const MAX_PNG_CHUNKS: usize = 4_096;
const MAX_PNG_SIZE: usize = 12 * 1024 * 1024;
const PNG_SIGNATURE: &[u8; 8] = b"\x89PNG\r\n\x1a\n";

/// Transcode artwork to PNG and insert exactly one uncompressed credential chunk.
pub(crate) fn bake(source: &[u8], credential: &[u8]) -> Result<Vec<u8>> {
    // Reject source and credential payloads outside the fixed service limits
    if source.len() > MAX_PNG_SIZE || credential.len() > MAX_CREDENTIAL_SIZE {
        return Err(BadgeServiceError::PngLimitExceeded);
    }

    // Decode the source and require the badge artwork dimensions
    let image = ImageReader::new(Cursor::new(source))
        .with_guessed_format()
        .map_err(|_| BadgeServiceError::InvalidImage)?
        .decode()
        .map_err(|_| BadgeServiceError::InvalidImage)?;
    if image.dimensions() != (512, 512) {
        return Err(BadgeServiceError::InvalidImage);
    }

    // Transcode to PNG before inserting the unique credential chunk
    let mut png = Cursor::new(Vec::new());
    image
        .write_to(&mut png, ImageFormat::Png)
        .map_err(|_| BadgeServiceError::InvalidImage)?;
    insert_credential_chunk(png.into_inner(), credential)
}

/// Extract the unique, uncompressed Open Badges credential chunk.
pub(crate) fn extract(png: &[u8]) -> Result<Vec<u8>> {
    // Validate the bounded PNG envelope before parsing chunks
    if png.len() > MAX_PNG_SIZE || !png.starts_with(PNG_SIGNATURE) {
        return Err(BadgeServiceError::InvalidPng);
    }
    validate_png_image(png)?;

    // Scan the complete chunk stream for exactly one credential and one terminator
    let mut cursor = PNG_SIGNATURE.len();
    let mut credential = None;
    let mut chunks = 0;
    let mut found_iend = false;
    while cursor < png.len() {
        chunks += 1;
        if chunks > MAX_PNG_CHUNKS {
            return Err(BadgeServiceError::PngLimitExceeded);
        }
        let (kind, data, next) = read_chunk(png, cursor)?;
        cursor = next;
        if kind == ITXT && data.starts_with(CREDENTIAL_KEYWORD) {
            let text = parse_credential_itxt(data)?;
            if credential.replace(text.to_vec()).is_some() {
                return Err(BadgeServiceError::InvalidPng);
            }
        }
        if kind == IEND {
            found_iend = true;
            if cursor != png.len() {
                return Err(BadgeServiceError::InvalidPng);
            }
            break;
        }
    }

    if !found_iend {
        return Err(BadgeServiceError::InvalidPng);
    }

    // Return only the unique validated credential payload
    credential.ok_or(BadgeServiceError::InvalidPng)
}

/// Encode a PNG chunk with its library-computed CRC.
fn encode_chunk(kind: [u8; 4], data: &[u8]) -> Result<Vec<u8>> {
    let length = u32::try_from(data.len()).map_err(|_| BadgeServiceError::PngLimitExceeded)?;
    let mut chunk = Vec::with_capacity(data.len() + 12);
    chunk.extend_from_slice(&length.to_be_bytes());
    chunk.extend_from_slice(&kind);
    chunk.extend_from_slice(data);
    let mut hasher = Hasher::new();
    hasher.update(&kind);
    hasher.update(data);
    chunk.extend_from_slice(&hasher.finalize().to_be_bytes());
    Ok(chunk)
}

/// Insert the credential immediately before IEND in a freshly transcoded PNG.
fn insert_credential_chunk(mut png: Vec<u8>, credential: &[u8]) -> Result<Vec<u8>> {
    let mut cursor = PNG_SIGNATURE.len();
    let mut iend_offset = None;
    while cursor < png.len() {
        let (kind, _, next) = read_chunk(&png, cursor)?;
        if kind == IEND {
            iend_offset = Some(cursor);
            break;
        }
        cursor = next;
    }
    let iend_offset = iend_offset.ok_or(BadgeServiceError::InvalidPng)?;

    let mut data = Vec::with_capacity(CREDENTIAL_KEYWORD.len() + credential.len() + 5);
    data.extend_from_slice(CREDENTIAL_KEYWORD);
    data.extend_from_slice(&[0, 0, 0, 0, 0]);
    data.extend_from_slice(credential);
    let chunk = encode_chunk(*ITXT, &data)?;
    png.splice(iend_offset..iend_offset, chunk);
    Ok(png)
}

/// Parse and validate the exact uncompressed iTXt layout used by Open Badges.
fn parse_credential_itxt(data: &[u8]) -> Result<&[u8]> {
    let prefix_length = CREDENTIAL_KEYWORD.len() + 5;
    if data.len() > prefix_length + MAX_CREDENTIAL_SIZE
        || data.get(..CREDENTIAL_KEYWORD.len()) != Some(CREDENTIAL_KEYWORD)
        || data.get(CREDENTIAL_KEYWORD.len()..prefix_length) != Some(&[0, 0, 0, 0, 0][..])
    {
        return Err(BadgeServiceError::InvalidPng);
    }
    Ok(&data[prefix_length..])
}

/// Read one bounded PNG chunk and verify its CRC.
fn read_chunk(png: &[u8], offset: usize) -> Result<(&[u8; 4], &[u8], usize)> {
    let header = png.get(offset..offset + 8).ok_or(BadgeServiceError::InvalidPng)?;
    let length = usize::try_from(u32::from_be_bytes(
        header[..4].try_into().map_err(|_| BadgeServiceError::InvalidPng)?,
    ))
    .map_err(|_| BadgeServiceError::InvalidPng)?;
    if length > MAX_PNG_SIZE {
        return Err(BadgeServiceError::PngLimitExceeded);
    }
    let end = offset
        .checked_add(12)
        .and_then(|value| value.checked_add(length))
        .ok_or(BadgeServiceError::InvalidPng)?;
    let chunk = png.get(offset..end).ok_or(BadgeServiceError::InvalidPng)?;
    let kind: &[u8; 4] = chunk[4..8].try_into().map_err(|_| BadgeServiceError::InvalidPng)?;
    let data = &chunk[8..8 + length];
    let expected_crc = u32::from_be_bytes(
        chunk[8 + length..12 + length]
            .try_into()
            .map_err(|_| BadgeServiceError::InvalidPng)?,
    );
    let mut hasher = Hasher::new();
    hasher.update(kind);
    hasher.update(data);
    if hasher.finalize() != expected_crc {
        return Err(BadgeServiceError::InvalidPng);
    }

    Ok((kind, data, end))
}

/// Decode the uploaded PNG within strict credential-artwork limits.
fn validate_png_image(png: &[u8]) -> Result<()> {
    let mut limits = Limits::default();
    limits.max_alloc = Some(16 * 1024 * 1024);
    limits.max_image_height = Some(512);
    limits.max_image_width = Some(512);
    let mut reader = ImageReader::with_format(Cursor::new(png), ImageFormat::Png);
    reader.limits(limits);
    let image = reader.decode().map_err(|_| BadgeServiceError::InvalidPng)?;
    if image.dimensions() != (512, 512) {
        return Err(BadgeServiceError::InvalidPng);
    }
    Ok(())
}
