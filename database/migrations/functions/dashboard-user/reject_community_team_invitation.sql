-- Rejects a pending community team invitation for a user.
create or replace function reject_community_team_invitation(
    p_actor_user_id uuid,
    p_community_id uuid
)
returns void as $$
begin
    -- Remove the pending invitation
    delete from community_team ct
    where ct.community_id = p_community_id
      and ct.user_id = p_actor_user_id
      and ct.accepted = false;

    if not found then
        raise exception 'no pending community invitation found';
    end if;

    -- Track the rejected invitation
    perform insert_audit_log(
        'community_team_invitation_rejected',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        p_community_id
    );
end;
$$ language plpgsql;
