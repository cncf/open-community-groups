-- Returns public co-host group credits for an event.
-- Uses PL/pgSQL with `force_generic_plan` so each connection caches its plan:
-- event lists call it once per event, and a SQL-language body is planned
-- again on each call (PostgreSQL 17 and earlier). The setting also keeps a
-- caller's `force_custom_plan` from planning it on every call.
create or replace function event_cohosts_json(p_event_id uuid)
returns jsonb as $$
begin
    -- Collect the event's public co-host group credits
    return (
        select coalesce(
            jsonb_agg(
                jsonb_strip_nulls(jsonb_build_object(
                    'community_display_name', c.display_name,
                    'community_name', c.name,
                    'group_id', g.group_id,
                    'logo_url', coalesce(g.logo_url, c.logo_url),
                    'name', g.name,
                    'slug', g.slug,

                    -- Pair the dark logo with the level that provides the light logo
                    'logo_dark_url', paired_dark_image_url(
                        g.logo_url, g.logo_dark_url,
                        c.logo_url, c.logo_dark_url
                    ),
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
        and g.deleted = false
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_generic_plan;
