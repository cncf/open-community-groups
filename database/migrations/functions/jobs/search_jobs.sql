create or replace function search_jobs(p_filters jsonb)
returns jsonb language plpgsql stable as $$
declare
    v_limit int := coalesce((p_filters->>'limit')::int, 20);
    v_offset int := coalesce((p_filters->>'offset')::int, 0);
    v_query text := nullif(trim(p_filters->>'query'), '');
    v_location text := nullif(trim(p_filters->>'location'), '');
    v_remote boolean := (p_filters->>'remote')::boolean;
    v_include_members_only boolean := coalesce((p_filters->>'include_members_only')::boolean, false);
    v_total int;
    v_jobs jsonb;
begin
    with matches as (
        select j.*
        from jobs_job j
        where j.published = true
        and j.expires_at > current_timestamp
        and (v_include_members_only or j.members_only = false)
        and (
            v_query is null
            or j.title ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or j.company_name ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or j.summary ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or j.description ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or exists (
                select 1
                from unnest(j.tags) tag
                where tag ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            )
        )
        and (
            v_location is null
            or j.location ilike '%' || escape_ilike_pattern(v_location) || '%' escape '\'
        )
        and (v_remote is null or j.remote = v_remote)
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
