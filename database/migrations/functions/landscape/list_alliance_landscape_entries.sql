create or replace function list_alliance_landscape_entries(
    p_alliance_id uuid,
    p_filters jsonb
) returns jsonb language plpgsql stable as $$
declare
    v_limit int := coalesce((p_filters->>'limit')::int, 50);
    v_offset int := coalesce((p_filters->>'offset')::int, 0);
    v_query text := nullif(trim(p_filters->>'query'), '');
    v_total int;
    v_entries jsonb;
begin
    with matches as (
        select le.*
        from landscape_entry le
        where le.alliance_id = p_alliance_id
        and (
            v_query is null
            or le.name ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or le.summary ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or le.description ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or le.category ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            or exists (
                select 1
                from unnest(le.tags) tag
                where tag ilike '%' || escape_ilike_pattern(v_query) || '%' escape '\'
            )
        )
    ),
    counted as (
        select count(*)::int as total from matches
    ),
    paged as (
        select *
        from matches
        order by created_at desc, landscape_entry_id desc
        limit v_limit
        offset v_offset
    )
    select
        counted.total,
        coalesce(
            jsonb_agg(landscape_entry_json(paged) order by paged.created_at desc, paged.landscape_entry_id desc)
                filter (where paged.landscape_entry_id is not null),
            '[]'::jsonb
        )
    into v_total, v_entries
    from counted
    left join paged on true
    group by counted.total;

    return jsonb_build_object(
        'entries', coalesce(v_entries, '[]'::jsonb),
        'total', coalesce(v_total, 0)
    );
end;
$$;
