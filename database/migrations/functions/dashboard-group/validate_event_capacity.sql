-- validate_event_capacity validates provider limits and update attendee floors.
create or replace function validate_event_capacity(
    p_event jsonb,
    p_cfg_max_participants jsonb default null,
    p_existing_event_id uuid default null
)
returns void as $$
declare
    v_attendee_count int;
    v_capacity int := (p_event->>'capacity')::int;
    v_provider_max_participants int;
begin
    -- Validate waitlist configuration against capacity requirements
    if coalesce((p_event->>'waitlist_enabled')::boolean, false) = true and v_capacity is null then
        raise exception 'waitlist enabled events must define a capacity';
    end if;

    -- Validate event capacity against provider limits for meetings
    if (p_event->>'meeting_requested')::boolean = true then
        v_provider_max_participants := (p_cfg_max_participants->>(p_event->>'meeting_provider_id'))::int;

        if v_provider_max_participants is not null
           and v_capacity > v_provider_max_participants
        then
            raise exception 'event capacity (%) exceeds maximum participants allowed (%)',
                v_capacity, v_provider_max_participants;
        end if;
    end if;

    -- Validate event capacity against attendee count for existing events
    if p_existing_event_id is not null and v_capacity is not null then
        select count(*) into v_attendee_count
        from event_attendee
        where event_id = p_existing_event_id;

        if v_capacity < v_attendee_count then
            raise exception 'event capacity (%) cannot be less than current number of attendees (%)',
                v_capacity, v_attendee_count;
        end if;
    end if;
end;
$$ language plpgsql;
