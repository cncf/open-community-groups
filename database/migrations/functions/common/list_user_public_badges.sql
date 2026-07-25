-- Lists active profile-visible badges for a community user.
create or replace function list_user_public_badges(
    p_community_id uuid,
    p_username text,
    p_limit integer default 50,
    p_offset integer default 0
)
returns json as $$
declare
    v_badges json;
    v_limit integer := coalesce(p_limit, 50);
    v_offset integer := coalesce(p_offset, 0);
begin
    -- Validate normalized pagination
    if v_limit <= 0 or v_limit > 50 or v_offset < 0 then
        raise exception 'badge pagination is outside the supported range';
    end if;

    -- Query active public badges in stable profile order
    select coalesce(
        json_agg(
            row.badge
            order by row.display_order, row.awarded_at desc, row.user_badge_id
        ),
        '[]'::json
    )
    into v_badges
    from (
        select json_build_object(
            'snapshot', json_build_object(
                'image_file_name', ub.snapshot->>'image_file_name',
                'issuer', json_build_object(
                    'group_name', ub.snapshot#>>'{issuer,group_name}'
                ),
                'name', ub.snapshot->>'name'
            ),
            'user_badge_id', ub.user_badge_id
        ) badge,
        ub.awarded_at,
        ub.display_order,
        ub.user_badge_id
        from user_badge ub
        join "group" g using (group_id)
        join "user" u using (user_id)
        where g.community_id = p_community_id
        and lower(u.username) = lower(p_username)
        and ub.is_listed = true
        and ub.revoked_at is null
        order by ub.display_order, ub.awarded_at desc, ub.user_badge_id
        limit v_limit
        offset v_offset
    ) row;

    return v_badges;
end;
$$ language plpgsql;
