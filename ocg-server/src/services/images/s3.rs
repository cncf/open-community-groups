//! S3-compatible image storage implementation.

use anyhow::{Context, Result};
use async_trait::async_trait;
use aws_credential_types::{Credentials, provider::SharedCredentialsProvider};
use aws_sdk_s3::{
    Client as S3Client,
    config::{BehaviorVersion, Region},
    error::SdkError as S3SdkError,
    primitives::ByteStream,
};
use tracing::{instrument, trace};

use crate::config::ImageStorageConfigS3;

use super::{Image, ImageStorage, NewImage};

/// S3-compatible image storage implementation.
pub(crate) struct S3ImageStorage {
    /// Name of the bucket where images are stored.
    bucket: String,
    /// AWS SDK client configured for the provider.
    client: S3Client,
}

impl S3ImageStorage {
    /// Create a new S3-compatible storage instance using the provided configuration.
    pub(crate) fn new(cfg: &ImageStorageConfigS3) -> Self {
        // Setup S3 configuration
        let credentials = Credentials::new(
            &cfg.access_key_id,
            &cfg.secret_access_key,
            None,
            None,
            "ocg-image-storage",
        );
        let mut builder = aws_sdk_s3::Config::builder()
            .behavior_version(BehaviorVersion::latest())
            .credentials_provider(SharedCredentialsProvider::new(credentials))
            .region(Region::new(cfg.region.clone()));
        if let Some(endpoint) = &cfg.endpoint {
            builder = builder.endpoint_url(endpoint);
        }
        builder = builder.force_path_style(cfg.force_path_style.unwrap_or(true));

        // Create S3 client
        let client = S3Client::from_conf(builder.build());

        Self {
            bucket: cfg.bucket.clone(),
            client,
        }
    }
}

#[async_trait]
impl ImageStorage for S3ImageStorage {
    #[instrument(skip(self), err)]
    async fn get(&self, file_name: &str) -> Result<Option<Image>> {
        trace!("images: load image from s3");

        match self
            .client
            .get_object()
            .bucket(&self.bucket)
            .key(file_name)
            .send()
            .await
        {
            Ok(output) => {
                let content_type = output.content_type().map(str::to_string);
                let bytes = output
                    .body
                    .collect()
                    .await
                    .context("error reading s3 object body")?
                    .into_bytes()
                    .to_vec();
                let content_type = content_type.unwrap_or_else(|| {
                    mime_guess::from_path(file_name)
                        .first_or_octet_stream()
                        .essence_str()
                        .to_string()
                });
                Ok(Some(Image { bytes, content_type }))
            }
            Err(err) => {
                if let S3SdkError::ServiceError(service_err) = &err
                    && service_err.err().is_no_such_key()
                {
                    return Ok(None);
                }
                Err(err.into())
            }
        }
    }

    #[instrument(skip(self, image), fields(file_name = %image.file_name), err)]
    async fn save(&self, image: &NewImage<'_>) -> Result<()> {
        trace!("images: save image to s3");

        let body = ByteStream::from(image.bytes.to_vec());
        self.client
            .put_object()
            .bucket(&self.bucket)
            .key(image.file_name)
            .body(body)
            .content_type(image.content_type)
            .metadata("created-by", image.user_id.to_string())
            .send()
            .await?;

        Ok(())
    }
}
