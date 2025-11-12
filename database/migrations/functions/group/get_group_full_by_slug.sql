-- Returns detailed information about a group by its slug and community ID.
create or replace function get_group_full_by_slug(p_community_id uuid, p_group_slug text)
returns json as $$
    select get_group_full(p_community_id, g.group_id)
    from "group" g
    where g.community_id = p_community_id
    and g.slug = p_group_slug
    and g.active = true;
$$ language sql;
