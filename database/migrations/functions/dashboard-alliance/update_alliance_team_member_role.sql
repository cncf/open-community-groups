-- Updates a alliance team member's role.
create or replace function update_alliance_team_member_role(
    p_actor_user_id uuid,
    p_alliance_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
declare
    v_accepted_admins integer;
    v_current_accepted boolean;
    v_current_role text;
begin
    -- Lock current alliance team rows to avoid concurrent final-admin demotions
    perform 1
    from alliance_team
    where alliance_id = p_alliance_id
    order by user_id
    for update;

    -- Load current membership details before role change
    select
        ct.accepted,
        ct.role
    into
        v_current_accepted,
        v_current_role
    from alliance_team ct
    where ct.alliance_id = p_alliance_id
      and ct.user_id = p_user_id;

    -- Ensure membership exists
    if not found then
        raise exception 'user is not a alliance team member';
    end if;

    -- Update role for an existing alliance team member
    -- This ensures invalid roles fail with the FK error before business checks
    update alliance_team
    set role = p_role
    where alliance_id = p_alliance_id
      and user_id = p_user_id;

    -- Prevent demoting the last accepted alliance admin
    if v_current_accepted and v_current_role = 'admin' and p_role <> 'admin' then
        select count(*)::int
        into v_accepted_admins
        from alliance_team ct
        where ct.alliance_id = p_alliance_id
          and ct.accepted = true
          and ct.role = 'admin';

        if v_accepted_admins = 0 then
            raise exception 'cannot change role for the last accepted alliance admin';
        end if;
    end if;

    -- Track the role update
    perform insert_audit_log(
        'alliance_team_member_role_updated',
        p_actor_user_id,
        'user',
        p_user_id,
        p_alliance_id,
        null,
        null,
        jsonb_build_object('role', p_role)
    );
end;
$$ language plpgsql;
