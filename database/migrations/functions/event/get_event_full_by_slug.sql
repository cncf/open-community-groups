-- Returns detailed information about an event by its slug, group slug and community ID.
create or replace function get_event_full_by_slug(p_community_id uuid, p_group_slug text, p_event_slug text)
returns json as $$
    select get_event_full(p_community_id, g.group_id, e.event_id)
    from event e
    join "group" g using (group_id)
    where g.community_id = p_community_id
    and g.slug = p_group_slug
    and e.slug = p_event_slug
    and g.active = true
    and e.published = true;
$$ language sql;
