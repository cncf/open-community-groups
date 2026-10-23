-- Lists current and upcoming events carrying the user's check-in credential.
create or replace function list_user_check_in_events(p_user_id uuid)
returns json as $$
    select coalesce(json_agg(event_row order by in_progress desc, starts_at), '[]'::json)
    from (
        select
            ea.checked_in,
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
            event_attendee_ticket_title(ea.event_id, ea.user_id) as ticket_title,

            e.starts_at <= current_timestamp as in_progress
        from event_attendee ea
        join event e using (event_id)
        join "group" g using (group_id)
        join community c using (community_id)
        where ea.user_id = p_user_id
        and ea.status = 'confirmed'
        and is_event_check_in_open(e, g)
    ) event_row;
$$ language sql stable;
