-- Deletes a user from the community team.
create or replace function delete_community_team_member(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_user_id uuid
) returns void as $$
declare
    v_is_accepted boolean;
    v_role text;
begin
    -- Lock current community team rows to avoid concurrent final-member removals
    perform 1
    from community_team
    where community_id = p_community_id
    order by user_id
    for update;

    -- Load target membership details
    select
        ct.accepted,
        ct.role
    into
        v_is_accepted,
        v_role
    from community_team ct
    where ct.community_id = p_community_id
      and ct.user_id = p_user_id;

    -- Raise error if membership does not exist
    if not found then
        raise exception 'user is not a community team member' using errcode = 'OCG01';
    end if;

    -- Prevent removing the last accepted community admin
    if v_is_accepted
       and v_role = 'admin'
       and not community_team_has_other_accepted_admin(p_community_id, p_user_id) then
        raise exception 'cannot remove the last accepted community admin' using errcode = 'OCG01';
    end if;

    -- Delete the membership record
    delete from community_team
    where community_id = p_community_id
      and user_id = p_user_id;

    -- Track the removal
    perform insert_audit_log(
        'community_team_member_removed',
        p_actor_user_id,
        'user',
        p_user_id,
        p_community_id
    );
end;
$$ language plpgsql;
