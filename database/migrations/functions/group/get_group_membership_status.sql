-- Return membership and pending join-request status for a user.
create or replace function get_group_membership_status(
    p_alliance_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns json as $$
    select json_build_object(
        'is_member', exists (
            select 1
            from group_member gm
            where gm.group_id = p_group_id
            and gm.user_id = p_user_id
        ),
        'approval_required', coalesce(g.membership_approval_required, false),
        'has_pending_request', exists (
            select 1
            from group_join_request gjr
            where gjr.group_id = p_group_id
            and gjr.user_id = p_user_id
            and gjr.status = 'pending'
        )
    )
    from "group" g
    where g.group_id = p_group_id
    and g.alliance_id = p_alliance_id
    and g.active = true
    and g.deleted = false;
$$ language sql stable;
