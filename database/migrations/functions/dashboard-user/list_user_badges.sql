-- Lists active badges owned by a dashboard user.
create or replace function list_user_badges(p_user_id uuid)
returns json as $$
    select coalesce(
        json_agg(row_to_json(ub) order by ub.display_order, ub.awarded_at desc, ub.user_badge_id),
        '[]'::json
    )
    from user_badge ub
    where ub.user_id = p_user_id
    and ub.revoked_at is null;
$$ language sql;
