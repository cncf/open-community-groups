create or replace function search_landscape_entries(p_filters jsonb)
returns jsonb language plpgsql stable as $$
declare
    v_limit int := coalesce((p_filters->>'limit')::int, 20);
    v_offset int := coalesce((p_filters->>'offset')::int, 0);
    v_query text := nullif(trim(p_filters->>'query'), '');
    v_kind text := nullif(trim(p_filters->>'kind'), '');
    v_category text := nullif(trim(p_filters->>'category'), '');
    v_alliance text := nullif(trim(p_filters->>'alliance'), '');
    v_total int;
    v_entries jsonb;
begin
    with matches as (
        select le.*
        from landscape_entry le
        join alliance a on a.alliance_id = le.alliance_id
        where le.published = true
        and (v_alliance is null or a.name = v_alliance)
        and (v_kind is null or le.kind = v_kind)
        and (
            v_category is null
            or le.category ilike '%' || escape_ilike_pattern(v_category) || '%' escape '\'
        )
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
