//! Image type definitions.

/// Image returned from a storage provider.
#[derive(Debug, Clone)]
pub(crate) struct Image {
    /// Image contents.
    pub bytes: Vec<u8>,
    /// MIME type set when the image was retrieved.
    pub content_type: String,
}
