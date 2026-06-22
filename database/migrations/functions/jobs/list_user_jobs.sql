create or replace function list_user_jobs(p_user_id uuid, p_filters jsonb)
returns jsonb language plpgsql stable as $$
declare
    v_limit int := coalesce((p_filters->>'limit')::int, 20);
    v_offset int := coalesce((p_filters->>'offset')::int, 0);
    v_total int;
    v_jobs jsonb;
begin
    with matches as (
        select *
        from jobs_job
        where posted_by_user_id = p_user_id
    ),
    counted as (
        select count(*)::int as total from matches
    ),
    paged as (
        select *
        from matches
        order by created_at desc, job_id desc
        limit v_limit
        offset v_offset
    )
    select
        counted.total,
        coalesce(
            jsonb_agg(job_summary_json(paged) order by paged.created_at desc, paged.job_id desc)
                filter (where paged.job_id is not null),
            '[]'::jsonb
        )
    into v_total, v_jobs
    from counted
    left join paged on true
    group by counted.total;

    return jsonb_build_object(
        'jobs', coalesce(v_jobs, '[]'::jsonb),
        'total', coalesce(v_total, 0)
    );
end;
$$;
