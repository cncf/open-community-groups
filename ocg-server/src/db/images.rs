//! Database functionality for storing and retrieving images.

use anyhow::Result;
use async_trait::async_trait;
use tracing::{instrument, trace};
use uuid::Uuid;

use crate::{db::PgDB, services::images::Image};

/// Trait describing database operations for images.
#[async_trait]
pub(crate) trait DBImages {
    /// Retrieves an image by file name.
    async fn get_image(&self, file_name: &str) -> Result<Option<Image>>;

    /// Saves the provided image.
    async fn save_image(&self, user_id: Uuid, file_name: &str, data: &[u8], content_type: &str)
    -> Result<()>;
}

#[async_trait]
impl DBImages for PgDB {
    #[instrument(skip(self), err)]
    async fn get_image(&self, file_name: &str) -> Result<Option<Image>> {
        trace!("db: get image");

        let db = self.pool.get().await?;
        let image = db
            .query_opt(
                "
                select data, content_type
                from images
                where file_name = $1::text;
                ",
                &[&file_name],
            )
            .await?
            .map(|row| Image {
                bytes: row.get("data"),
                content_type: row.get("content_type"),
            });

        Ok(image)
    }

    #[instrument(skip(self, data, content_type), err)]
    async fn save_image(
        &self,
        user_id: Uuid,
        file_name: &str,
        data: &[u8],
        content_type: &str,
    ) -> Result<()> {
        trace!("db: save image");

        let db = self.pool.get().await?;
        db.execute(
            "
            insert into images (created_by, file_name, data, content_type)
            values ($1::uuid, $2::text, $3::bytea, $4::text)
            on conflict (file_name) do nothing;
            ",
            &[&file_name, &user_id, &data, &content_type],
        )
        .await?;

        Ok(())
    }
}
