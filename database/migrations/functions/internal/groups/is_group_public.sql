-- Checks whether a group is publicly visible: active and not deleted. Marked
-- parallel safe so parallel queries calling it keep their parallel plans.
create or replace function is_group_public(p_group "group")
returns boolean as $$
    select p_group.active = true
        and p_group.deleted = false;
$$ language sql immutable parallel safe;
