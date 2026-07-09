-- Returns whether a group has active, visible subgroups.
create or replace function group_has_active_subgroups(
    p_community_id uuid,
    p_group_id uuid
) returns boolean as $$
    select exists (
        select 1
        from "group" child
        where child.community_id = p_community_id
        and child.parent_group_id = p_group_id
        and child.active = true
        and child.deleted = false
    );
$$ language sql stable;
