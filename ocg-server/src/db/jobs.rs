//! Database operations for jobs.

use anyhow::Result;
use async_trait::async_trait;
use tokio_postgres::types::Json;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    types::jobs::{
        DashboardJobsFilters, DashboardJobsOutput, JobApplicationInput, JobFull, JobInput,
        JobsFilters, JobsOutput, parse_tags,
    },
};

/// Database operations for the jobs product area.
#[async_trait]
pub(crate) trait DBJobs {
    /// Search published jobs.
    async fn search_jobs(&self, filters: &JobsFilters) -> Result<JobsOutput>;

    /// Get a public job by slug.
    async fn get_job_by_slug(&self, slug: &str, viewer_user_id: Option<Uuid>) -> Result<JobFull>;

    /// List jobs owned by a user.
    async fn list_user_jobs(
        &self,
        user_id: Uuid,
        filters: &DashboardJobsFilters,
    ) -> Result<DashboardJobsOutput>;

    /// Add a job owned by a user.
    async fn add_job(&self, user_id: Uuid, input: &JobInput) -> Result<Uuid>;

    /// Update a job owned by a user.
    async fn update_job(&self, user_id: Uuid, job_id: Uuid, input: &JobInput) -> Result<()>;

    /// Delete a job owned by a user.
    async fn delete_job(&self, user_id: Uuid, job_id: Uuid) -> Result<()>;

    /// Toggle job publishing status.
    async fn update_job_published(
        &self,
        user_id: Uuid,
        job_id: Uuid,
        published: bool,
    ) -> Result<()>;

    /// Add an application for a job.
    async fn add_job_application(
        &self,
        user_id: Uuid,
        job_id: Uuid,
        input: &JobApplicationInput,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBJobs for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self, filters), err)]
    async fn search_jobs(&self, filters: &JobsFilters) -> Result<JobsOutput> {
        self.fetch_json_one("select search_jobs($1::jsonb)", &[&Json(filters)])
            .await
    }

    #[instrument(skip(self), err)]
    async fn get_job_by_slug(&self, slug: &str, viewer_user_id: Option<Uuid>) -> Result<JobFull> {
        self.fetch_json_one(
            "select get_job_by_slug($1::text, $2::uuid)",
            &[&slug, &viewer_user_id],
        )
        .await
    }

    #[instrument(skip(self, filters), err)]
    async fn list_user_jobs(
        &self,
        user_id: Uuid,
        filters: &DashboardJobsFilters,
    ) -> Result<DashboardJobsOutput> {
        self.fetch_json_one(
            "select list_user_jobs($1::uuid, $2::jsonb)",
            &[&user_id, &Json(filters)],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_job(&self, user_id: Uuid, input: &JobInput) -> Result<Uuid> {
        let tags = parse_tags(input.tags.as_deref());
        self.fetch_scalar_one(
            "select add_job($1::uuid, $2::jsonb, $3::text[])",
            &[&user_id, &Json(input), &tags],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn update_job(&self, user_id: Uuid, job_id: Uuid, input: &JobInput) -> Result<()> {
        let tags = parse_tags(input.tags.as_deref());
        self.execute(
            "select update_job($1::uuid, $2::uuid, $3::jsonb, $4::text[])",
            &[&user_id, &job_id, &Json(input), &tags],
        )
        .await?;
        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn delete_job(&self, user_id: Uuid, job_id: Uuid) -> Result<()> {
        self.execute(
            "select delete_job($1::uuid, $2::uuid)",
            &[&user_id, &job_id],
        )
        .await?;
        Ok(())
    }

    #[instrument(skip(self), err)]
    async fn update_job_published(
        &self,
        user_id: Uuid,
        job_id: Uuid,
        published: bool,
    ) -> Result<()> {
        self.execute(
            "select update_job_published($1::uuid, $2::uuid, $3::boolean)",
            &[&user_id, &job_id, &published],
        )
        .await?;
        Ok(())
    }

    #[instrument(skip(self, input), err)]
    async fn add_job_application(
        &self,
        user_id: Uuid,
        job_id: Uuid,
        input: &JobApplicationInput,
    ) -> Result<()> {
        self.execute(
            "select add_job_application($1::uuid, $2::uuid, $3::jsonb)",
            &[&user_id, &job_id, &Json(input)],
        )
        .await?;
        Ok(())
    }
}
