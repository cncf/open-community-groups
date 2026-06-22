-- Accepts a pending alliance team invitation for a user.
create or replace function accept_alliance_team_invitation(
    p_actor_user_id uuid,
    p_alliance_id uuid
) returns void as $$
begin
    -- Accept the pending invitation
    update alliance_team ct
    set accepted = true
    where ct.alliance_id = p_alliance_id
      and ct.user_id = p_actor_user_id
      and ct.accepted = false;

    -- Ensure a pending invitation exists
    if not found then
        raise exception 'no pending alliance invitation found';
    end if;

    -- Track the accepted invitation
    perform insert_audit_log(
        'alliance_team_invitation_accepted',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        p_alliance_id
    );
end;
$$ language plpgsql;
