-- Returns one active badge owned by a dashboard user.
create or replace function get_user_badge(p_user_id uuid, p_user_badge_id uuid)
returns json as $$
    select user_badge_json(ub, true)::json
    from user_badge ub
    where ub.user_badge_id = p_user_badge_id
    and ub.user_id = p_user_id
    and ub.revoked_at is null;
$$ language sql stable;
