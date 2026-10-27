-- Deletes a user from the group team.
create or replace function delete_group_team_member(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
declare
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
        raise exception 'user is not a group team member' using errcode = 'OCG01';
    end if;

    -- Prevent removing the last accepted group admin
    if v_is_accepted
       and v_role = 'admin'
       and not group_team_has_other_accepted_admin(p_group_id, p_user_id) then
        raise exception 'cannot remove the last accepted group admin' using errcode = 'OCG01';
    end if;

    -- Delete the membership record
    delete from group_team
    where group_id = p_group_id
      and user_id = p_user_id;

    -- Track the removal
    perform insert_audit_log(
        'group_team_member_removed',
        p_actor_user_id,
        'user',
        p_user_id,
        p_group_id => p_group_id
    );
end;
$$ language plpgsql;
