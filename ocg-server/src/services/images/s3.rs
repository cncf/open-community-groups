//! S3-compatible image storage implementation.

use std::time::Duration;

use anyhow::{Context, Result};
use async_trait::async_trait;
use aws_credential_types::{Credentials, provider::SharedCredentialsProvider};
use aws_sdk_s3::{
    Client as S3Client,
    config::{BehaviorVersion, Region, timeout::TimeoutConfig},
    error::SdkError as S3SdkError,
    primitives::ByteStream,
};
use tokio::time::{Instant, timeout};
use tracing::{instrument, trace};

use crate::{config::ImageStorageConfigS3, types::images::Image};

use super::{ImageStorage, NewImage};

#[cfg(test)]
mod tests;

/// S3-compatible image storage implementation.
pub(crate) struct S3ImageStorage {
    /// Name of the bucket where images are stored.
    bucket: String,
    /// AWS SDK client configured for the provider.
    client: S3Client,
    /// Total deadline for one S3 request, including reading the response body.
    request_timeout: Duration,
}

impl S3ImageStorage {
    /// Create a new S3-compatible storage instance using the provided configuration.
    pub(crate) fn new(cfg: &ImageStorageConfigS3) -> Self {
        // Configure outbound deadlines covering connection, first byte, and attempts
        let connect_timeout = cfg.connect_timeout();
        let request_timeout = cfg.request_timeout();
        let timeout_config = TimeoutConfig::builder()
            .connect_timeout(connect_timeout)
            .operation_attempt_timeout(request_timeout)
            .operation_timeout(request_timeout)
            .read_timeout(request_timeout)
            .build();

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
            .region(Region::new(cfg.region.clone()))
            .timeout_config(timeout_config);
        if let Some(endpoint) = &cfg.endpoint {
            builder = builder.endpoint_url(endpoint);
        }
        builder = builder.force_path_style(cfg.force_path_style.unwrap_or(true));

        // Create S3 client
        let client = S3Client::from_conf(builder.build());

        Self {
            bucket: cfg.bucket.clone(),
            client,
            request_timeout,
        }
    }
}

#[async_trait]
impl ImageStorage for S3ImageStorage {
    #[instrument(skip(self), err)]
    async fn get(&self, file_name: &str) -> Result<Option<Image>> {
        trace!("images: load image from s3");

        // Track a single total deadline across the SDK request and body stream read
        let started_at = Instant::now();

        // Fetch object metadata and response stream from S3
        let output = match self
            .client
            .get_object()
            .bucket(&self.bucket)
            .key(file_name)
            .send()
            .await
        {
            Ok(output) => output,
            Err(err) => {
                if let S3SdkError::ServiceError(service_err) = &err
                    && service_err.err().is_no_such_key()
                {
                    return Ok(None);
                }
                return Err(err.into());
            }
        };

        // Read the response body within the remaining request deadline
        let content_type = output.content_type().map(str::to_string);
        let remaining = self.request_timeout.saturating_sub(started_at.elapsed());
        let bytes = timeout(remaining, output.body.collect())
            .await
            .context("timed out reading s3 object body")?
            .context("error reading s3 object body")?
            .into_bytes()
            .to_vec();

        // Fall back to MIME detection from the file name when S3 omits content type
        let content_type = content_type.unwrap_or_else(|| {
            mime_guess::from_path(file_name)
                .first_or_octet_stream()
                .essence_str()
                .to_string()
        });

        Ok(Some(Image {
            bytes,
            content_type,
        }))
    }

    #[instrument(skip(self, image), fields(file_name = %image.file_name), err)]
    async fn save(&self, image: &NewImage<'_>) -> Result<()> {
        trace!("images: save image to s3");

        // Upload the object with content type and creator metadata
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
