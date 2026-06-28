-- Join a group as a member.
create or replace function join_group(
    p_alliance_id uuid,
    p_group_id uuid,
    p_user_id uuid
) returns text as $$
declare
    v_membership_approval_required boolean;
begin
    -- Check if group exists, is active and not deleted
    select membership_approval_required
    into v_membership_approval_required
    from "group"
    where group_id = p_group_id
    and alliance_id = p_alliance_id
    and active = true
    and deleted = false;

    if not found then
        raise exception 'group not found or inactive';
    end if;

    if exists (
        select 1
        from group_member
        where group_id = p_group_id
        and user_id = p_user_id
    ) then
        raise exception 'user is already a member of this group';
    end if;

    if v_membership_approval_required then
        insert into group_join_request (
            group_id,
            user_id,
            status,
            reviewed_at,
            reviewed_by
        ) values (
            p_group_id,
            p_user_id,
            'pending',
            null,
            null
        )
        on conflict (group_id, user_id) do update set
            status = 'pending',
            created_at = current_timestamp,
            reviewed_at = null,
            reviewed_by = null;

        return 'pending';
    end if;

    -- Add user to group
    begin
        insert into group_member (group_id, user_id)
        values (p_group_id, p_user_id);
    exception
        when unique_violation then
            raise exception 'user is already a member of this group';
    end;

    return 'joined';
end;
$$ language plpgsql;
