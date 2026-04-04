-- Accepts a pending group team invitation for a user.
create or replace function accept_group_team_invitation(p_actor_user_id uuid, p_group_id uuid)
returns void as $$
begin
    -- Accept the pending invitation
    update group_team gt
    set accepted = true
    where gt.group_id = p_group_id
      and gt.user_id = p_actor_user_id
      and gt.accepted = false;

    -- Ensure a pending invitation exists
    if not found then
        raise exception 'no pending group invitation found';
    end if;

    -- Track the accepted invitation
    perform insert_audit_log(
        'group_team_invitation_accepted',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        (select community_id from "group" where group_id = p_group_id),
        p_group_id
    );
end;
$$ language plpgsql;
