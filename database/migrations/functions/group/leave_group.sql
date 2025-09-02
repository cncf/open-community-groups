-- Leave a group as a member.
create or replace function leave_group(
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

    -- Remove user from group
    delete from group_member
    where group_id = p_group_id
    and user_id = p_user_id;

    if not found then
        raise exception 'user is not a member of this group';
    end if;
end;
$$ language plpgsql;
