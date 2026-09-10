-- Locks a group that still accepts dashboard mutations and returns its row.
-- The group must belong to the community and must not be soft-deleted; the
-- `active` visibility flag is not required because activation itself is one
-- of the mutations that starts here.
create or replace function lock_active_group(
    p_community_id uuid,
    p_group_id uuid
)
returns "group" as $$
declare
    v_group "group";
begin
    select g.*
    into v_group
    from "group" g
    where g.group_id = p_group_id
    and g.community_id = p_community_id
    and g.deleted = false
    for update of g;

    if not found then
        raise exception 'group not found or inactive' using errcode = 'OCG01';
    end if;

    return v_group;
end;
$$ language plpgsql;
