-- Deletes a user from the alliance team.
create or replace function delete_alliance_team_member(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_user_id uuid
) returns void as $$
declare
    v_accepted_admins integer;
    v_is_accepted boolean;
    v_role text;
begin
    -- Lock current alliance team rows to avoid concurrent final-member removals
    perform 1
    from alliance_team
    where alliance_id = p_alliance_id
    order by user_id
    for update;

    -- Load target membership details
    select
        ct.accepted,
        ct.role
    into
        v_is_accepted,
        v_role
    from alliance_team ct
    where ct.alliance_id = p_alliance_id
      and ct.user_id = p_user_id;

    -- Raise error if membership does not exist
    if not found then
        raise exception 'user is not a alliance team member';
    end if;

    -- Prevent removing the last accepted alliance admin
    if v_is_accepted and v_role = 'admin' then
        select count(*)::int
        into v_accepted_admins
        from alliance_team ct
        where ct.alliance_id = p_alliance_id
          and ct.accepted = true
          and ct.role = 'admin';

        if v_accepted_admins = 1 then
            raise exception 'cannot remove the last accepted alliance admin';
        end if;
    end if;

    -- Delete the membership record
    delete from alliance_team
    where alliance_id = p_alliance_id
      and user_id = p_user_id;

    -- Track the removal
    perform insert_audit_log(
        'alliance_team_member_removed',
        p_actor_user_id,
        'user',
        p_user_id,
        p_alliance_id
    );
end;
$$ language plpgsql;
