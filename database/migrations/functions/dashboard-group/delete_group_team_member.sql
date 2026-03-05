-- Deletes a user from the group team.
create or replace function delete_group_team_member(
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
declare
    v_accepted_admins integer;
    v_is_accepted boolean;
    v_role text;
begin
    -- Lock current group team rows to avoid concurrent final-member removals
    perform 1
    from group_team
    where group_id = p_group_id
    order by user_id
    for update;

    -- Load target membership details
    select
        gt.accepted,
        gt.role
    into
        v_is_accepted,
        v_role
    from group_team gt
    where gt.group_id = p_group_id
      and gt.user_id = p_user_id;

    -- Raise error if membership does not exist
    if not found then
        raise exception 'user is not a group team member';
    end if;

    -- Prevent removing the last accepted group admin
    if v_is_accepted and v_role = 'admin' then
        select count(*)::int
        into v_accepted_admins
        from group_team gt
        where gt.group_id = p_group_id
          and gt.accepted = true
          and gt.role = 'admin';

        if v_accepted_admins = 1 then
            raise exception 'cannot remove the last accepted group admin';
        end if;
    end if;

    -- Delete the membership record
    delete from group_team
    where group_id = p_group_id
      and user_id = p_user_id;
end;
$$ language plpgsql;
