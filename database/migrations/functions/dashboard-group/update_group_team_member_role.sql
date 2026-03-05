-- Updates a group team member's role.
create or replace function update_group_team_member_role(
    p_group_id uuid,
    p_user_id uuid,
    p_role text
) returns void as $$
declare
    v_accepted_admins integer;
    v_current_accepted boolean;
    v_current_role text;
begin
    -- Lock current group team rows to avoid concurrent final-admin demotions
    perform 1
    from group_team
    where group_id = p_group_id
    order by user_id
    for update;

    -- Load current membership details before role change
    select
        gt.accepted,
        gt.role
    into
        v_current_accepted,
        v_current_role
    from group_team gt
    where gt.group_id = p_group_id
      and gt.user_id = p_user_id;

    -- Ensure membership exists
    if not found then
        raise exception 'user is not a group team member';
    end if;

    -- Update role for an existing group team member
    -- This ensures invalid roles fail with the FK error before business checks
    update group_team
    set role = p_role
    where group_id = p_group_id
      and user_id = p_user_id;

    -- Prevent demoting the last accepted group admin
    if v_current_accepted and v_current_role = 'admin' and p_role <> 'admin' then
        select count(*)::int
        into v_accepted_admins
        from group_team gt
        where gt.group_id = p_group_id
          and gt.accepted = true
          and gt.role = 'admin';

        if v_accepted_admins = 0 then
            raise exception 'cannot change role for the last accepted group admin';
        end if;
    end if;
end;
$$ language plpgsql;
