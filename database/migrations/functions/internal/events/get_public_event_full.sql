-- Returns public full information about an event: the organizer projection
-- without organizer-only configuration and secrets, with inventory limited to
-- attendee-visible public tiers.
create or replace function get_public_event_full(
    p_community_id uuid,
    p_group_id uuid,
    p_event_id uuid
)
returns json as $$
    with
    -- Build the organizer projection once
    full_event as (
        select get_event_full(p_community_id, p_group_id, p_event_id)::jsonb as event_json
    ),
    -- Keep the attendee-visible ticket types of that projection
    public_ticket_projection as (
        select event_ticket_types_public_json(fe.event_json->'ticket_types') as ticket_types
        from full_event fe
    ),
    -- Sum inventory from ticket types currently visible to attendees
    public_ticket_inventory as (
        select
            sum((ticket_type->>'seats_total')::int)::int as capacity,
            sum((ticket_type->>'remaining_seats')::int)::int as remaining_capacity
        from public_ticket_projection ptp
        cross join lateral jsonb_array_elements(
            coalesce(ptp.ticket_types, '[]'::jsonb)
        ) as public_ticket_types(ticket_type)
        where (ticket_type->>'active')::boolean
        and ticket_type ? 'current_price'
    ),
    -- Remove organizer-only meeting fields from every session
    public_sessions as (
        select coalesce(
            jsonb_object_agg(day.key, (
                select jsonb_agg(
                    session.value - array[
                        'meeting_error',
                        'meeting_hosts',
                        'meeting_in_sync',
                        'meeting_password',
                        'meeting_recording_raw_urls',
                        'meeting_recording_url',
                        'meeting_requested'
                    ]
                    order by session.position
                )
                from jsonb_array_elements(day.value)
                    with ordinality as session(value, position)
            )),
            '{}'::jsonb
        ) as sessions
        from full_event fe
        cross join lateral jsonb_each(fe.event_json->'sessions') as day(key, value)
    )
    -- Replace organizer inventory and drop organizer-only configuration and secrets
    select (
        (
            fe.event_json - array[
                'capacity',
                'discount_codes',
                'manual_tax_rate_ids',
                'meeting_error',
                'meeting_hosts',
                'meeting_in_sync',
                'meeting_password',
                'meeting_recording_raw_urls',
                'meeting_recording_requested',
                'meeting_recording_url',
                'meeting_requested',
                'registration_questions_locked',
                'remaining_capacity',
                'sessions',
                'ticket_types'
            ]
        )
        || jsonb_build_object('sessions', ps.sessions)
        || jsonb_strip_nulls(
            jsonb_build_object(
                'capacity', pti.capacity,
                'remaining_capacity', pti.remaining_capacity,
                'ticket_types', ptp.ticket_types
            )
        )
    )::json
    from full_event fe
    cross join public_sessions ps
    cross join public_ticket_inventory pti
    cross join public_ticket_projection ptp;
$$ language sql stable;
