-- Join a group as a member.
create or replace function join_group(
    p_community_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns void as $$
begin
    -- Check if group exists, is active and not deleted
    if not exists (
        select 1
        from "group"
        where group_id = p_group_id
        and community_id = p_community_id
        and active = true
        and deleted = false
    ) then
        raise exception 'group not found or inactive';
    end if;

    -- Add user to group
    begin
        insert into group_member (group_id, user_id)
        values (p_group_id, p_user_id);
    exception
        when unique_violation then
            raise exception 'user is already a member of this group';
    end;
end;
$$ language plpgsql;
