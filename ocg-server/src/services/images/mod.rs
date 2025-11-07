//! Image storage service abstractions and shared types.

pub(crate) mod db;
pub(crate) mod s3;

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use uuid::Uuid;

pub(crate) use db::DbImageStorage;
pub(crate) use s3::S3ImageStorage;

/// Trait representing the capabilities required from an image storage provider.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait ImageStorage {
    /// Retrieve an image by its file name from the storage provider.
    async fn get(&self, file_name: &str) -> Result<Option<Image>>;

    /// Save the provided image to the storage provider.
    async fn save(&self, image: &NewImage<'_>) -> Result<()>;
}

/// Trait object type for image storage providers.
pub(crate) type DynImageStorage = Arc<dyn ImageStorage + Send + Sync>;

/// Image returned from a storage provider.
#[derive(Debug, Clone)]
pub(crate) struct Image {
    /// Image contents.
    pub bytes: Vec<u8>,
    /// MIME type set when the image was retrieved.
    pub content_type: String,
}

/// Image to be uploaded to a storage provider.
pub(crate) struct NewImage<'a> {
    /// Image contents.
    pub bytes: &'a [u8],
    /// MIME type determined for the image.
    pub content_type: &'a str,
    /// Target file name (hash plus extension).
    pub file_name: &'a str,
    /// Identifier of the user that uploaded the image.
    pub user_id: Uuid,
}
