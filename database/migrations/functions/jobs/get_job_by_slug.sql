create or replace function get_job_by_slug(p_slug text, p_viewer_user_id uuid default null)
returns jsonb language plpgsql stable as $$
declare
    v_job jobs_job;
begin
    select *
    into v_job
    from jobs_job
    where slug = p_slug
    and published = true
    and expires_at > current_timestamp;

    if v_job.job_id is null then
        raise exception 'job not found';
    end if;

    return job_summary_json(v_job) || jsonb_build_object(
        'viewer_has_applied', exists (
            select 1
            from jobs_application ja
            where ja.job_id = v_job.job_id
            and ja.applicant_user_id = p_viewer_user_id
        )
    );
end;
$$;
