//! Image management and storage service abstractions.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
#[cfg(test)]
use mockall::automock;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    services::blocking::BlockingExecutor,
    types::images::{Image, ImageTarget},
    util::compute_hash,
};

use self::validation::{ImageValidationError, validate_badge_artwork, validate_image_upload};

pub(crate) mod db;
pub(crate) mod s3;
pub(crate) mod validation;

#[cfg(test)]
mod tests;

pub(crate) use db::DbImageStorage;
pub(crate) use s3::S3ImageStorage;

/// Maximum payload size allowed for image uploads (1 MiB).
pub(crate) const MAX_IMAGE_SIZE_BYTES: usize = 1024 * 1024;

/// Image management workflows used by HTTP handlers.
#[async_trait]
#[cfg_attr(test, automock)]
pub(crate) trait ImagesManager {
    /// Retrieves an image by its stored file name.
    async fn get(&self, file_name: &str) -> Result<Option<Image>, ImagesError>;

    /// Validates, hashes, and persists an uploaded image, returning its stored file name.
    async fn upload(&self, input: UploadImageInput) -> Result<String, ImagesError>;

    /// Loads and validates a stored image against the badge artwork contract.
    async fn validate_badge_artwork(&self, file_name: &str) -> Result<(), ImagesError>;
}

/// Shared image manager trait object.
pub(crate) type DynImagesManager = Arc<dyn ImagesManager + Send + Sync>;

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

/// Errors returned by [`ImagesManager`] operations.
#[derive(Debug, thiserror::Error)]
pub(crate) enum ImagesError {
    /// Unexpected storage, blocking executor, or internal failure.
    #[error(transparent)]
    Other(#[from] anyhow::Error),
    /// User-facing validation or lookup rejection.
    #[error("{0}")]
    Rejected(String),
}

impl From<ImageValidationError> for ImagesError {
    fn from(err: ImageValidationError) -> Self {
        Self::Rejected(err.to_string())
    }
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

/// Input for validating and storing an uploaded image.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct UploadImageInput {
    /// Raw uploaded image bytes.
    pub bytes: Vec<u8>,
    /// Original uploaded file name used to verify the extension.
    pub file_name: String,
    /// Identifier of the user uploading the image.
    pub user_id: Uuid,

    /// Optional upload target enforcing format and dimension constraints.
    pub target: Option<ImageTarget>,
}

/// Default [`ImagesManager`] backed by an [`ImageStorage`] provider and a shared [`BlockingExecutor`].
pub(crate) struct DefaultImagesManager {
    /// Bounded executor used for CPU-heavy image validation and hashing.
    blocking_executor: BlockingExecutor,
    /// Underlying image storage provider.
    storage: DynImageStorage,
}

impl DefaultImagesManager {
    /// Creates a new `DefaultImagesManager`.
    pub(crate) fn new(blocking_executor: BlockingExecutor, storage: DynImageStorage) -> Self {
        Self {
            blocking_executor,
            storage,
        }
    }
}

#[async_trait]
impl ImagesManager for DefaultImagesManager {
    /// [`ImagesManager::get`].
    #[instrument(skip(self))]
    async fn get(&self, file_name: &str) -> Result<Option<Image>, ImagesError> {
        Ok(self.storage.get(file_name).await?)
    }

    /// [`ImagesManager::upload`].
    #[instrument(
        skip(self, input),
        fields(bytes = input.bytes.len(), target = ?input.target, user_id = %input.user_id)
    )]
    async fn upload(&self, input: UploadImageInput) -> Result<String, ImagesError> {
        // Guard the maximum upload size before running CPU-heavy validation
        if input.bytes.len() > MAX_IMAGE_SIZE_BYTES {
            return Err(ImagesError::Rejected("image exceeds 1MB limit".to_string()));
        }

        // Validate the image and compute its content hash off the async runtime
        let UploadImageInput {
            bytes,
            file_name,
            user_id,
            target,
        } = input;
        let (bytes, content_type, stored_file_name) = self
            .blocking_executor
            .run(move || {
                let validated = validate_image_upload(&file_name, &bytes, target)?;
                let hash = compute_hash(&bytes);
                let stored_file_name = format!("{hash}.{}", validated.extension);
                Ok::<_, ImageValidationError>((bytes, validated.content_type, stored_file_name))
            })
            .await??;

        // Store the validated image under its content-addressed name
        let new_image = NewImage {
            bytes: &bytes,
            content_type,
            file_name: &stored_file_name,
            user_id,
        };
        self.storage.save(&new_image).await?;

        Ok(stored_file_name)
    }

    /// [`ImagesManager::validate_badge_artwork`].
    #[instrument(skip(self))]
    async fn validate_badge_artwork(&self, file_name: &str) -> Result<(), ImagesError> {
        // Load the stored object before running full raster decoding
        let image = self
            .storage
            .get(file_name)
            .await?
            .ok_or_else(|| ImagesError::Rejected("badge artwork was not found".to_string()))?;

        // Validate and decode the badge artwork off the async runtime
        let file_name = file_name.to_string();
        self.blocking_executor
            .run(move || validate_badge_artwork(&file_name, &image))
            .await??;

        Ok(())
    }
}
