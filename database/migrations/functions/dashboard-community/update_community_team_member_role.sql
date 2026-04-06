-- Updates a community team member's role.
create or replace function update_community_team_member_role(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
declare
    v_accepted_admins integer;
    v_current_accepted boolean;
    v_current_role text;
begin
    -- Lock current community team rows to avoid concurrent final-admin demotions
    perform 1
    from community_team
    where community_id = p_community_id
    order by user_id
    for update;

    -- Load current membership details before role change
    select
        ct.accepted,
        ct.role
    into
        v_current_accepted,
        v_current_role
    from community_team ct
    where ct.community_id = p_community_id
      and ct.user_id = p_user_id;

    -- Ensure membership exists
    if not found then
        raise exception 'user is not a community team member';
    end if;

    -- Update role for an existing community team member
    -- This ensures invalid roles fail with the FK error before business checks
    update community_team
    set role = p_role
    where community_id = p_community_id
      and user_id = p_user_id;

    -- Prevent demoting the last accepted community admin
    if v_current_accepted and v_current_role = 'admin' and p_role <> 'admin' then
        select count(*)::int
        into v_accepted_admins
        from community_team ct
        where ct.community_id = p_community_id
          and ct.accepted = true
          and ct.role = 'admin';

        if v_accepted_admins = 0 then
            raise exception 'cannot change role for the last accepted community admin';
        end if;
    end if;

    -- Track the role update
    perform insert_audit_log(
        'community_team_member_role_updated',
        p_actor_user_id,
        'user',
        p_user_id,
        p_community_id,
        null,
        null,
        jsonb_build_object('role', p_role)
    );
end;
$$ language plpgsql;
