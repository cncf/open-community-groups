-- Returns durable revocation state for a public badge status list.
create or replace function get_badge_status_list(p_badge_status_list_id uuid)
returns json as $$
    select json_build_object(
        'badge_status_list_id', bsl.badge_status_list_id,
        'group_id', bsl.group_id,
        'revoked_indexes', coalesce(
            array_agg(ub.status_list_index order by ub.status_list_index)
                filter (where ub.revoked_at is not null),
            '{}'::integer[]
        )
    )
    from badge_status_list bsl
    left join user_badge ub using (badge_status_list_id)
    where bsl.badge_status_list_id = p_badge_status_list_id
    group by bsl.badge_status_list_id, bsl.group_id;
$$ language sql;
