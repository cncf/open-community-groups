-- Checks whether an active (non-deleted) group belongs to a community.
create or replace function group_belongs_to_community(
    p_community_id uuid,
    p_group_id uuid
) returns boolean as $$
    select exists (
        select 1
        from "group" g
        where g.community_id = p_community_id
        and g.group_id = p_group_id
        and g.deleted = false
    );
$$ language sql;
