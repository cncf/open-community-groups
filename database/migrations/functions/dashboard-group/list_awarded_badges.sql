-- Lists searchable badge award history for a group.
create or replace function list_awarded_badges(p_group_id uuid, p_filters jsonb)
returns json as $$
    with
        -- Normalize pagination, search, and status filters
        filters as (
            select
                greatest(coalesce((p_filters->>'limit')::integer, 20), 1) as limit_value,
                greatest(coalesce((p_filters->>'offset')::integer, 0), 0) as offset_value,
                nullif(btrim(p_filters->>'query'), '') as query_value,

                nullif(p_filters->>'badge_id', '')::uuid as badge_id_value,
                nullif(p_filters->>'event_id', '')::uuid as event_id_value,
                nullif(p_filters->>'from', '')::timestamptz as from_value,
                nullif(p_filters->>'status', '') as status_value,
                nullif(p_filters->>'to', '')::timestamptz as to_value
        ),
        -- Apply group ownership plus all requested award filters
        filtered as (
            select
                ub.awarded_at,
                ub.badge_status_list_id,
                ub.display_order,
                ub.group_id,
                ub.is_listed,
                ub.snapshot,
                ub.status_list_index,
                ub.user_badge_id,

                ub.badge_id,
                ub.event_id,
                ub.revocation_reason,
                ub.revoked_at,
                ub.revoked_by_user_id,
                ub.user_id,

                e.name as event_name,
                coalesce(u.name, u.username) as recipient_name,
                u.username as recipient_username
            from user_badge ub
            left join event e on e.event_id = ub.event_id
            left join "user" u on u.user_id = ub.user_id
            cross join filters f
            where ub.group_id = p_group_id
            and (f.badge_id_value is null or ub.badge_id = f.badge_id_value)
            and (f.event_id_value is null or ub.event_id = f.event_id_value)
            and (f.from_value is null or ub.awarded_at >= f.from_value)
            and (f.to_value is null or ub.awarded_at < f.to_value)
            and (
                f.status_value is null
                or (f.status_value = 'active' and ub.revoked_at is null)
                or (f.status_value = 'revoked' and ub.revoked_at is not null)
            )
            and (
                f.query_value is null
                or ub.snapshot->>'name' ilike '%' || escape_ilike_pattern(f.query_value) || '%'
                or coalesce(u.name, '') ilike '%' || escape_ilike_pattern(f.query_value) || '%'
                or coalesce(u.username, '') ilike '%' || escape_ilike_pattern(f.query_value) || '%'
            )
        ),
        -- Select the requested page in stable newest-first order
        page as (
            select *
            from filtered
            order by awarded_at desc, user_badge_id desc
            offset (select offset_value from filters)
            limit (select limit_value from filters)
        )
    -- Return award rows and the unpaginated total
    select json_build_object(
        'awards', coalesce(
            (
                select json_agg(row_to_json(page) order by awarded_at desc, user_badge_id desc)
                from page
            ),
            '[]'::json
        ),
        'badges', coalesce(
            (
                select json_agg(row_to_json(definition) order by definition.name, definition.badge_id)
                from (
                    select b.badge_id, b.name
                    from badge b
                    where b.group_id = p_group_id
                    and exists (
                        select 1
                        from user_badge ub
                        where ub.badge_id = b.badge_id
                    )
                ) definition
            ),
            '[]'::json
        ),
        'sources', coalesce(
            (
                select json_agg(row_to_json(source) order by source.name, source.event_id)
                from (
                    select distinct e.event_id, e.name
                    from user_badge ub
                    join event e on e.event_id = ub.event_id
                    where ub.group_id = p_group_id
                ) source
            ),
            '[]'::json
        ),
        'total', (select count(*)::integer from filtered)
    );
$$ language sql;
