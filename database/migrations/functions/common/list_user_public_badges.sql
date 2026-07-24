-- Lists active profile-visible badges for a community user.
create or replace function list_user_public_badges(
    p_community_id uuid,
    p_username text
)
returns json as $$
    select coalesce(
        json_agg(
            json_build_object(
                'awarded_at', ub.awarded_at,
                'group_id', ub.group_id,
                'snapshot', ub.snapshot,
                'user_badge_id', ub.user_badge_id
            )
            order by ub.display_order, ub.awarded_at desc, ub.user_badge_id
        ),
        '[]'::json
    )
    from user_badge ub
    join "group" g using (group_id)
    join "user" u using (user_id)
    where g.community_id = p_community_id
    and lower(u.username) = lower(p_username)
    and ub.is_listed = true
    and ub.revoked_at is null;
$$ language sql;
