-- Returns detailed information about a group by its slug and alliance ID.
create or replace function get_group_full_by_slug(p_alliance_id uuid, p_group_slug text)
returns json as $$
    select get_group_full(p_alliance_id, g.group_id)
    from "group" g
    where g.alliance_id = p_alliance_id
    and (g.slug = p_group_slug or g.slug_pretty = p_group_slug)
    and g.active = true;
$$ language sql;
