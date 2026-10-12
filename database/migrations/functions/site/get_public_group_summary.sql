-- Returns the summary of a group when its public page is available, or null.
create or replace function get_public_group_summary(p_group_id uuid)
returns json as $$
    select get_group_summary(g.community_id, g.group_id)
    from "group" g
    join community c on c.community_id = g.community_id
    where g.group_id = p_group_id
    and c.active = true
    and is_group_public(g);
$$ language sql;
