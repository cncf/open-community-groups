//! Database-backed image storage implementation.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};

use crate::db::DynDB;

use super::{Image, ImageStorage, NewImage};

/// Database-backed image storage implementation.
pub(crate) struct DbImageStorage {
    /// Handle to the database abstraction layer.
    db: DynDB,
}

impl DbImageStorage {
    /// Create a new database-backed storage instance.
    pub(crate) fn new(db: DynDB) -> Self {
        Self { db }
    }
}

#[async_trait]
impl ImageStorage for DbImageStorage {
    #[instrument(skip(self), err)]
    async fn get(&self, file_name: &str) -> Result<Option<Image>> {
        trace!("images: load image from db");

        // Retrieve the image from the database
        let image = self.db.get_image(file_name).await?;

        Ok(image)
    }

    #[instrument(skip(self, image), fields(file_name = %image.file_name), err)]
    async fn save(&self, image: &NewImage<'_>) -> Result<()> {
        trace!("images: save image to db");

        // Save the image to the database
        self.db
            .save_image(image.user_id, image.file_name, image.bytes, image.content_type)
            .await
    }
}
