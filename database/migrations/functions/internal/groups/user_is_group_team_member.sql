-- Checks whether a user is an accepted member of a group team, whatever their
-- role. Pending team invitations do not count.
create or replace function user_is_group_team_member(p_group_id uuid, p_user_id uuid)
returns boolean as $$
    select exists (
        select 1
        from group_team gt
        where gt.group_id = p_group_id
        and gt.user_id = p_user_id
        and gt.accepted = true
    );
$$ language sql stable;
