-- validate_event_capacity validates provider limits and update attendee floors.
create or replace function validate_event_capacity(
    p_event jsonb,
    p_cfg_meeting_limits jsonb default null,
    p_existing_event_id uuid default null,
    p_effective_capacity int default null
)
returns void as $$
declare
    v_attendee_count int;
    v_capacity int := coalesce(p_effective_capacity, (p_event->>'capacity')::int);
    v_manual_occupied_seat_count int;
    v_provider_max_participants int;
    v_waitlist_enabled boolean := coalesce((p_event->>'waitlist_enabled')::boolean, false);
begin
    -- Validate waitlist configuration against capacity requirements
    if v_waitlist_enabled = true and v_capacity is null then
        raise exception 'waitlist enabled events must define a capacity' using errcode = 'OCG01';
    end if;

    -- Validate event capacity against provider limits for meetings
    if (p_event->>'meeting_requested')::boolean = true then
        -- Resolve the participant limit configured for the meeting provider
        v_provider_max_participants := (
            p_cfg_meeting_limits->(p_event->>'meeting_provider_id')->>'max_participants'
        )::int;

        -- Reject capacities above the configured participant limit
        if v_provider_max_participants is not null
           and v_capacity > v_provider_max_participants
        then
            raise exception 'event capacity (%) exceeds maximum participants allowed (%)',
                v_capacity, v_provider_max_participants using errcode = 'OCG01';
        end if;
    end if;

    -- Validate event capacity against attendee count for existing events
    if p_existing_event_id is not null and v_capacity is not null then
        -- Count the seats already occupied by attendees
        select get_event_occupied_seat_count(p_existing_event_id) into v_attendee_count;

        -- Manual occupied seats are organizer-controlled overbooked seats, so they offset the attendee floor
        select count(*)::int
        into v_manual_occupied_seat_count
        from event_attendee ea
        where ea.event_id = p_existing_event_id
        and ea.manually_invited = true
        and ea.status in ('confirmed', 'registration-questions-pending');

        -- Reject capacities below the attendee floor
        if v_capacity + v_manual_occupied_seat_count < v_attendee_count then
            raise exception 'event capacity (%) cannot be less than current number of attendees (%)',
                v_capacity, v_attendee_count using errcode = 'OCG01';
        end if;
    end if;
end;
$$ language plpgsql;
