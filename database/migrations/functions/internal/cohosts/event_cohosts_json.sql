-- Returns public co-host group credits for an event.
create or replace function event_cohosts_json(p_event_id uuid)
returns jsonb as $$
    select coalesce(
        jsonb_agg(
            jsonb_strip_nulls(jsonb_build_object(
                'community_display_name', c.display_name,
                'community_name', c.name,
                'group_id', g.group_id,
                'logo_url', coalesce(g.logo_url, c.logo_url),
                'name', g.name,
                'slug', g.slug,

                'slug_pretty', g.slug_pretty
            ))
            order by g.name asc, g.group_id asc
        ),
        '[]'::jsonb
    )
    from event_cohost ec
    join "group" g using (group_id)
    join community c using (community_id)
    where ec.event_id = p_event_id
    and (
        ec.event_cohost_status_id = 'approved'
        or (
            ec.event_cohost_status_id = 'event-canceled'
            and ec.approved_at is not null
        )
    )
    and c.active = true
    and g.active = true
    and g.deleted = false;
$$ language sql stable;
