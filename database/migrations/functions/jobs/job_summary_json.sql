create or replace function job_summary_json(p_job jobs_job)
returns jsonb language sql stable as $$
    select jsonb_build_object(
        'job_id', p_job.job_id,
        'title', p_job.title,
        'slug', p_job.slug,
        'company_name', p_job.company_name,
        'summary', p_job.summary,
        'description', p_job.description,
        'location', p_job.location,
        'remote', p_job.remote,
        'apply_url', p_job.apply_url,
        'tags', p_job.tags,
        'published', p_job.published,
        'application_count', (
            select count(*)::int
            from jobs_application ja
            where ja.job_id = p_job.job_id
        ),
        'posted_by_user_id', p_job.posted_by_user_id,
        'created_at', extract(epoch from p_job.created_at)::bigint,
        'updated_at', case
            when p_job.updated_at is null then null
            else extract(epoch from p_job.updated_at)::bigint
        end
    );
$$;
