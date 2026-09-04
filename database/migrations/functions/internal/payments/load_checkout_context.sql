-- Loads the event, group and community rows a checkout or purchase flow needs
-- for its summaries, notifications and seller settings. Callers lock the event
-- first; this read does not lock.
create or replace function load_checkout_context(p_event_id uuid)
returns table (
    community_row community,
    event_row event,
    group_row "group"
) as $$
    select c, e, g
    from event e
    join "group" g on g.group_id = e.group_id
    join community c on c.community_id = g.community_id
    where e.event_id = p_event_id;
$$ language sql stable;
