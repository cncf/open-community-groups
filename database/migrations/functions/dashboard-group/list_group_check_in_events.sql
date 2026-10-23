-- Lists current and upcoming events available to a group's scanner.
create or replace function list_group_check_in_events(p_group_id uuid)
returns json as $$
    select coalesce(json_agg(event_row order by in_progress desc, starts_at), '[]'::json)
    from (
        select
            e.event_id,
            e.event_kind_id as kind,
            e.name,
            epoch_seconds(e.starts_at) as starts_at,
            e.timezone,

            event_cohosts_json(e.event_id) as cohosts,
            coalesce(e.logo_url, g.logo_url, c.logo_url) as logo_url,
            nullif(concat_ws(
                ', ',
                e.venue_name,
                e.venue_city,
                e.venue_state_name,
                e.venue_country_name
            ), '') as location,

            e.starts_at <= current_timestamp as in_progress
        from event e
        join "group" g using (group_id)
        join community c using (community_id)
        where e.group_id = p_group_id
        and is_event_check_in_open(e, g)
    ) event_row;
$$ language sql stable;
