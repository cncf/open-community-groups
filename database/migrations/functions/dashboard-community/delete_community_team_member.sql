-- Deletes a user from the community team.
create or replace function delete_community_team_member(
    p_community_id uuid,
    p_user_id uuid
) returns void as $$
declare
    v_accepted_members integer;
    v_is_accepted boolean;
begin
    -- Lock current community team rows to avoid concurrent final-member removals
    perform 1
    from community_team
    where community_id = p_community_id
    order by user_id
    for update;

    -- Load target membership details
    select ct.accepted
    into v_is_accepted
    from community_team ct
    where ct.community_id = p_community_id
      and ct.user_id = p_user_id;

    -- Raise error if membership does not exist
    if not found then
        raise exception 'user is not a community team member';
    end if;

    -- Prevent removing the last accepted community team member
    if v_is_accepted then
        select count(*)::int
        into v_accepted_members
        from community_team ct
        where ct.community_id = p_community_id
          and ct.accepted = true;

        if v_accepted_members = 1 then
            raise exception 'cannot remove the last accepted community team member';
        end if;
    end if;

    -- Delete the membership record
    delete from community_team
    where community_id = p_community_id
      and user_id = p_user_id;
end;
$$ language plpgsql;
