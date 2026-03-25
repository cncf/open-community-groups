-- Accepts a pending community team invitation for a user.
create or replace function accept_community_team_invitation(
    p_actor_user_id uuid,
    p_community_id uuid
) returns void as $$
begin
    -- Accept the pending invitation
    update community_team ct
    set accepted = true
    where ct.community_id = p_community_id
      and ct.user_id = p_actor_user_id
      and ct.accepted = false;

    -- Ensure a pending invitation exists
    if not found then
        raise exception 'no pending community invitation found';
    end if;

    -- Track the accepted invitation
    perform insert_audit_log(
        'community_team_invitation_accepted',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        p_community_id
    );
end;
$$ language plpgsql;
