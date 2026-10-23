-- Locks a group that still accepts dashboard mutations and returns its row.
-- The group must not be soft-deleted and, when p_community_id is given, must
-- belong to that community; group dashboard callers that are already scoped by
-- group pass null. The `active` visibility flag is not required because
-- activation itself is one of the mutations that starts here.
create or replace function lock_active_group(
    p_community_id uuid,
    p_group_id uuid
)
returns "group" as $$
declare
    v_group "group";
begin
    -- Lock the group row within the optional community scope
    select g.*
    into v_group
    from "group" g
    where g.group_id = p_group_id
    and (p_community_id is null or g.community_id = p_community_id)
    and g.deleted = false
    for update of g;

    -- Reject missing, out-of-scope or soft-deleted groups
    if not found then
        raise exception 'group not found or inactive' using errcode = 'OCG01';
    end if;

    -- Return the locked group row
    return v_group;
end;
$$ language plpgsql;
