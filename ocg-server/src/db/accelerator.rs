//! Database operations for accelerator management.

use anyhow::Result;
use async_trait::async_trait;
use tracing::instrument;
use uuid::Uuid;

use crate::{
    db::PgExecutor,
    templates::dashboard::group::accelerator::{
        AcceleratorApplicationInput, AcceleratorApplicationReviewInput, AcceleratorCohortInput,
        AcceleratorDashboard, AcceleratorProgramInput, AcceleratorWeekInput,
        AcceleratorWeeklyUpdateInput, AcceleratorWeeklyUpdateReviewInput,
    },
};

/// Database operations for group accelerator programs.
#[async_trait]
pub(crate) trait DBAccelerator {
    /// Lists the full accelerator dashboard payload for one group.
    async fn get_group_accelerator_dashboard(&self, group_id: Uuid)
    -> Result<AcceleratorDashboard>;

    /// Adds an accelerator program.
    async fn add_group_accelerator_program(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        input: &AcceleratorProgramInput,
    ) -> Result<Uuid>;

    /// Adds a cohort.
    async fn add_group_accelerator_cohort(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        input: &AcceleratorCohortInput,
    ) -> Result<Uuid>;

    /// Adds a curriculum week.
    async fn add_group_accelerator_week(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        input: &AcceleratorWeekInput,
    ) -> Result<Uuid>;

    /// Submits an application for a cohort.
    async fn submit_group_accelerator_application(
        &self,
        user_id: Uuid,
        group_id: Uuid,
        cohort_id: Uuid,
        input: &AcceleratorApplicationInput,
    ) -> Result<Uuid>;

    /// Reviews an application.
    async fn review_group_accelerator_application(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        application_id: Uuid,
        input: &AcceleratorApplicationReviewInput,
    ) -> Result<()>;

    /// Accepts an application and creates a cohort member.
    async fn accept_group_accelerator_application(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        application_id: Uuid,
    ) -> Result<Uuid>;

    /// Submits or replaces a member weekly update.
    async fn submit_group_accelerator_weekly_update(
        &self,
        user_id: Uuid,
        group_id: Uuid,
        week_id: Uuid,
        input: &AcceleratorWeeklyUpdateInput,
    ) -> Result<Uuid>;

    /// Reviews a weekly update.
    async fn review_group_accelerator_weekly_update(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        weekly_update_id: Uuid,
        input: &AcceleratorWeeklyUpdateReviewInput,
    ) -> Result<()>;
}

#[async_trait]
impl<T> DBAccelerator for T
where
    T: PgExecutor + Send + Sync,
{
    #[instrument(skip(self), err)]
    async fn get_group_accelerator_dashboard(
        &self,
        group_id: Uuid,
    ) -> Result<AcceleratorDashboard> {
        self.fetch_json_one(
            r#"
            with programs as (
                select gap.*
                from group_accelerator_program gap
                where gap.group_id = $1::uuid
            ),
            cohorts as (
                select gac.*
                from group_accelerator_cohort gac
                join programs gap on gap.group_accelerator_program_id = gac.group_accelerator_program_id
            ),
            applications as (
                select gaa.*
                from group_accelerator_application gaa
                join cohorts gac on gac.group_accelerator_cohort_id = gaa.group_accelerator_cohort_id
            ),
            members as (
                select gam.*
                from group_accelerator_member gam
                join cohorts gac on gac.group_accelerator_cohort_id = gam.group_accelerator_cohort_id
            ),
            weeks as (
                select gaw.*
                from group_accelerator_week gaw
                join cohorts gac on gac.group_accelerator_cohort_id = gaw.group_accelerator_cohort_id
            ),
            weekly_updates as (
                select gawu.*
                from group_accelerator_weekly_update gawu
                join members gam on gam.group_accelerator_member_id = gawu.group_accelerator_member_id
                join cohorts gac on gac.group_accelerator_cohort_id = gam.group_accelerator_cohort_id
            )
            select jsonb_build_object(
                'programs', coalesce((select jsonb_agg(jsonb_build_object(
                    'group_accelerator_program_id', group_accelerator_program_id,
                    'group_id', group_id,
                    'name', name,
                    'summary', summary,
                    'description', description,
                    'application_url', application_url,
                    'curriculum_url', curriculum_url,
                    'active', active,
                    'created_at', extract(epoch from created_at)::bigint,
                    'updated_at', extract(epoch from updated_at)::bigint
                ) order by created_at desc) from programs), '[]'::jsonb),
                'cohorts', coalesce((select jsonb_agg(jsonb_build_object(
                    'group_accelerator_cohort_id', group_accelerator_cohort_id,
                    'group_accelerator_program_id', group_accelerator_program_id,
                    'name', name,
                    'status', status,
                    'starts_on', starts_on,
                    'ends_on', ends_on,
                    'application_deadline', application_deadline,
                    'capacity', capacity,
                    'created_at', extract(epoch from created_at)::bigint
                ) order by starts_on desc nulls last, created_at desc) from cohorts), '[]'::jsonb),
                'applications', coalesce((select jsonb_agg(jsonb_build_object(
                    'group_accelerator_application_id', group_accelerator_application_id,
                    'group_accelerator_cohort_id', group_accelerator_cohort_id,
                    'user_id', user_id,
                    'applicant_name', applicant_name,
                    'applicant_email', applicant_email,
                    'project_name', project_name,
                    'project_url', project_url,
                    'pitch', pitch,
                    'goals', goals,
                    'status', status,
                    'reviewer_notes', reviewer_notes,
                    'created_at', extract(epoch from created_at)::bigint
                ) order by created_at desc) from applications), '[]'::jsonb),
                'members', coalesce((select jsonb_agg(jsonb_build_object(
                    'group_accelerator_member_id', group_accelerator_member_id,
                    'group_accelerator_cohort_id', group_accelerator_cohort_id,
                    'user_id', user_id,
                    'display_name', display_name,
                    'project_name', project_name,
                    'project_url', project_url,
                    'status', status,
                    'created_at', extract(epoch from created_at)::bigint
                ) order by created_at desc) from members), '[]'::jsonb),
                'weeks', coalesce((select jsonb_agg(jsonb_build_object(
                    'group_accelerator_week_id', group_accelerator_week_id,
                    'group_accelerator_cohort_id', group_accelerator_cohort_id,
                    'week_number', week_number,
                    'title', title,
                    'goals', goals,
                    'resources_url', resources_url,
                    'deliverable', deliverable,
                    'starts_on', starts_on,
                    'due_on', due_on,
                    'created_at', extract(epoch from created_at)::bigint
                ) order by week_number) from weeks), '[]'::jsonb),
                'weekly_updates', coalesce((select jsonb_agg(jsonb_build_object(
                    'group_accelerator_weekly_update_id', group_accelerator_weekly_update_id,
                    'group_accelerator_member_id', group_accelerator_member_id,
                    'group_accelerator_week_id', group_accelerator_week_id,
                    'user_id', user_id,
                    'shipped', shipped,
                    'metrics', metrics,
                    'blockers', blockers,
                    'asks', asks,
                    'links', links,
                    'status', status,
                    'reviewer_notes', reviewer_notes,
                    'created_at', extract(epoch from created_at)::bigint
                ) order by created_at desc) from weekly_updates), '[]'::jsonb)
            )
            "#,
            &[&group_id],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_group_accelerator_program(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        input: &AcceleratorProgramInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r#"
            insert into group_accelerator_program (
                group_id, created_by, name, summary, description, application_url, curriculum_url, active
            )
            values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8)
            returning group_accelerator_program_id
            "#,
            &[
                &group_id,
                &actor_user_id,
                &input.name,
                &input.summary,
                &input.description,
                &input.application_url,
                &input.curriculum_url,
                &input.active,
            ],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_group_accelerator_cohort(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        input: &AcceleratorCohortInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r#"
            insert into group_accelerator_cohort (
                group_accelerator_program_id, created_by, name, status, starts_on, ends_on, application_deadline, capacity
            )
            select gap.group_accelerator_program_id, $2::uuid, $3, $4, $5::text::date, $6::text::date, $7::text::date, $8
            from group_accelerator_program gap
            where gap.group_id = $1::uuid
            and gap.group_accelerator_program_id = $9::uuid
            returning group_accelerator_cohort_id
            "#,
            &[
                &group_id,
                &actor_user_id,
                &input.name,
                &input.status,
                &input.starts_on,
                &input.ends_on,
                &input.application_deadline,
                &input.capacity,
                &input.group_accelerator_program_id,
            ],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn add_group_accelerator_week(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        input: &AcceleratorWeekInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r#"
            insert into group_accelerator_week (
                group_accelerator_cohort_id, created_by, week_number, title, goals, resources_url, deliverable, starts_on, due_on
            )
            select gac.group_accelerator_cohort_id, $2::uuid, $3, $4, $5, $6, $7, $8::text::date, $9::text::date
            from group_accelerator_cohort gac
            join group_accelerator_program gap on gap.group_accelerator_program_id = gac.group_accelerator_program_id
            where gap.group_id = $1::uuid
            and gac.group_accelerator_cohort_id = $10::uuid
            on conflict (group_accelerator_cohort_id, week_number) do update
            set title = excluded.title,
                goals = excluded.goals,
                resources_url = excluded.resources_url,
                deliverable = excluded.deliverable,
                starts_on = excluded.starts_on,
                due_on = excluded.due_on,
                updated_at = current_timestamp
            returning group_accelerator_week_id
            "#,
            &[
                &group_id,
                &actor_user_id,
                &input.week_number,
                &input.title,
                &input.goals,
                &input.resources_url,
                &input.deliverable,
                &input.starts_on,
                &input.due_on,
                &input.group_accelerator_cohort_id,
            ],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn submit_group_accelerator_application(
        &self,
        user_id: Uuid,
        group_id: Uuid,
        cohort_id: Uuid,
        input: &AcceleratorApplicationInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r#"
            insert into group_accelerator_application (
                group_accelerator_cohort_id, user_id, applicant_name, applicant_email, project_name, project_url, pitch, goals
            )
            select gac.group_accelerator_cohort_id, $2::uuid, $3, $4, $5, $6, $7, $8
            from group_accelerator_cohort gac
            join group_accelerator_program gap on gap.group_accelerator_program_id = gac.group_accelerator_program_id
            where gap.group_id = $1::uuid
            and gac.group_accelerator_cohort_id = $9::uuid
            returning group_accelerator_application_id
            "#,
            &[
                &group_id,
                &user_id,
                &input.applicant_name,
                &input.applicant_email,
                &input.project_name,
                &input.project_url,
                &input.pitch,
                &input.goals,
                &cohort_id,
            ],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn review_group_accelerator_application(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        application_id: Uuid,
        input: &AcceleratorApplicationReviewInput,
    ) -> Result<()> {
        self.execute(
            r#"
            update group_accelerator_application gaa
            set status = $3,
                reviewer_notes = $4,
                reviewed_by = $5::uuid,
                reviewed_at = current_timestamp,
                updated_at = current_timestamp
            from group_accelerator_cohort gac
            join group_accelerator_program gap on gap.group_accelerator_program_id = gac.group_accelerator_program_id
            where gaa.group_accelerator_cohort_id = gac.group_accelerator_cohort_id
            and gap.group_id = $1::uuid
            and gaa.group_accelerator_application_id = $2::uuid
            "#,
            &[
                &group_id,
                &application_id,
                &input.status,
                &input.reviewer_notes,
                &actor_user_id,
            ],
        )
        .await
    }

    #[instrument(skip(self), err)]
    async fn accept_group_accelerator_application(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        application_id: Uuid,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r#"
            with accepted as (
                update group_accelerator_application gaa
                set status = 'accepted',
                    reviewed_by = $2::uuid,
                    reviewed_at = current_timestamp,
                    updated_at = current_timestamp
                from group_accelerator_cohort gac
                join group_accelerator_program gap on gap.group_accelerator_program_id = gac.group_accelerator_program_id
                where gaa.group_accelerator_cohort_id = gac.group_accelerator_cohort_id
                and gap.group_id = $1::uuid
                and gaa.group_accelerator_application_id = $3::uuid
                returning gaa.*
            )
            insert into group_accelerator_member (
                group_accelerator_cohort_id,
                group_accelerator_application_id,
                user_id,
                display_name,
                project_name,
                project_url
            )
            select
                group_accelerator_cohort_id,
                group_accelerator_application_id,
                user_id,
                applicant_name,
                project_name,
                project_url
            from accepted
            on conflict (group_accelerator_cohort_id, group_accelerator_application_id) do update
            set status = 'active',
                updated_at = current_timestamp
            returning group_accelerator_member_id
            "#,
            &[&group_id, &actor_user_id, &application_id],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn submit_group_accelerator_weekly_update(
        &self,
        user_id: Uuid,
        group_id: Uuid,
        week_id: Uuid,
        input: &AcceleratorWeeklyUpdateInput,
    ) -> Result<Uuid> {
        self.fetch_scalar_one(
            r#"
            insert into group_accelerator_weekly_update (
                group_accelerator_member_id,
                group_accelerator_week_id,
                user_id,
                shipped,
                metrics,
                blockers,
                asks,
                links
            )
            select gam.group_accelerator_member_id, gaw.group_accelerator_week_id, $2::uuid, $3, $4, $5, $6, $7
            from group_accelerator_member gam
            join group_accelerator_cohort gac on gac.group_accelerator_cohort_id = gam.group_accelerator_cohort_id
            join group_accelerator_program gap on gap.group_accelerator_program_id = gac.group_accelerator_program_id
            join group_accelerator_week gaw on gaw.group_accelerator_cohort_id = gac.group_accelerator_cohort_id
            where gap.group_id = $1::uuid
            and gaw.group_accelerator_week_id = $8::uuid
            and gam.group_accelerator_member_id = $9::uuid
            and (gam.user_id is null or gam.user_id = $2::uuid)
            on conflict (group_accelerator_member_id, group_accelerator_week_id) do update
            set shipped = excluded.shipped,
                metrics = excluded.metrics,
                blockers = excluded.blockers,
                asks = excluded.asks,
                links = excluded.links,
                status = 'submitted',
                reviewer_notes = null,
                reviewed_by = null,
                reviewed_at = null,
                updated_at = current_timestamp
            returning group_accelerator_weekly_update_id
            "#,
            &[
                &group_id,
                &user_id,
                &input.shipped,
                &input.metrics,
                &input.blockers,
                &input.asks,
                &input.links,
                &week_id,
                &input.group_accelerator_member_id,
            ],
        )
        .await
    }

    #[instrument(skip(self, input), err)]
    async fn review_group_accelerator_weekly_update(
        &self,
        actor_user_id: Uuid,
        group_id: Uuid,
        weekly_update_id: Uuid,
        input: &AcceleratorWeeklyUpdateReviewInput,
    ) -> Result<()> {
        self.execute(
            r#"
            update group_accelerator_weekly_update gawu
            set status = $3,
                reviewer_notes = $4,
                reviewed_by = $5::uuid,
                reviewed_at = current_timestamp,
                updated_at = current_timestamp
            from group_accelerator_member gam
            join group_accelerator_cohort gac on gac.group_accelerator_cohort_id = gam.group_accelerator_cohort_id
            join group_accelerator_program gap on gap.group_accelerator_program_id = gac.group_accelerator_program_id
            where gawu.group_accelerator_member_id = gam.group_accelerator_member_id
            and gap.group_id = $1::uuid
            and gawu.group_accelerator_weekly_update_id = $2::uuid
            "#,
            &[
                &group_id,
                &weekly_update_id,
                &input.status,
                &input.reviewer_notes,
                &actor_user_id,
            ],
        )
        .await
    }
}
