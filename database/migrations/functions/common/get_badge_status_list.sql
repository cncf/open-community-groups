-- Returns durable revocation state for a public badge status list.
create or replace function get_badge_status_list(p_badge_status_list_id uuid)
returns json as $$
    select json_build_object(
        'badge_status_list_id', bsl.badge_status_list_id,
        'group_id', bsl.group_id,
        'revoked_indexes', array(
            select ub.status_list_index
            from user_badge ub
            where ub.badge_status_list_id = bsl.badge_status_list_id
            and ub.revoked_at is not null
            order by ub.status_list_index
        )
    )
    from badge_status_list bsl
    where bsl.badge_status_list_id = p_badge_status_list_id;
$$ language sql;
