-- Returns detailed information about an event by its slug, group slug and alliance ID.
create or replace function get_event_full_by_slug(p_alliance_id uuid, p_group_slug text, p_event_slug text)
returns json as $$
    select get_event_full(p_alliance_id, g.group_id, e.event_id)
    from event e
    join "group" g using (group_id)
    where g.alliance_id = p_alliance_id
    and (g.slug = p_group_slug or g.slug_pretty = p_group_slug)
    and e.slug = p_event_slug
    and e.deleted = false
    and g.active = true
    and e.published = true;
$$ language sql;
