-- Rejects a pending alliance team invitation for a user.
create or replace function reject_alliance_team_invitation(
    p_actor_user_id uuid,
    p_alliance_id uuid
)
returns void as $$
begin
    -- Remove the pending invitation
    delete from alliance_team ct
    where ct.alliance_id = p_alliance_id
      and ct.user_id = p_actor_user_id
      and ct.accepted = false;

    if not found then
        raise exception 'no pending alliance invitation found';
    end if;

    -- Track the rejected invitation
    perform insert_audit_log(
        'alliance_team_invitation_rejected',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        p_alliance_id
    );
end;
$$ language plpgsql;
