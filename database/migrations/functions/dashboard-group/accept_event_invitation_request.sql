-- Accepts an event invitation request and creates a confirmed attendee row.
create or replace function accept_event_invitation_request(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns void as $$
declare
    v_attendee_count int;
    v_attendee_status text;
    v_capacity int;
    v_alliance_id uuid;
    v_registration_ends_at timestamptz;
    v_registration_answers jsonb;
    v_registration_starts_at timestamptz;
    v_starts_at timestamptz;
begin
    -- Lock the event and verify it belongs to the selected group
    select
        e.capacity,
        g.alliance_id,
        e.registration_ends_at,
        e.registration_starts_at,
        e.starts_at
    into
        v_capacity,
        v_alliance_id,
        v_registration_ends_at,
        v_registration_starts_at,
        v_starts_at
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and e.group_id = p_group_id
    and g.active = true
    and e.attendee_approval_required = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false
    and (
        coalesce(e.ends_at, e.starts_at) is null
        or coalesce(e.ends_at, e.starts_at) >= current_timestamp
    )
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Attendee-requested invitations stay bound by the registration window
    if not is_registration_window_open(
        v_registration_starts_at,
        v_registration_ends_at,
        v_starts_at
    ) then
        raise exception 'event registration is not open';
    end if;

    -- Ensure the request is still pending and load any submitted registration answers
    select eir.registration_answers
    into v_registration_answers
    from event_invitation_request eir
    where eir.event_id = p_event_id
    and eir.user_id = p_user_id
    and eir.status = 'pending';

    if not found then
        raise exception 'pending invitation request not found';
    end if;

    -- Lock any existing attendee row and reject states the upsert below
    -- cannot convert, so acceptance is never recorded without attendance
    select ea.status
    into v_attendee_status
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_user_id
    for update of ea;

    if v_attendee_status = 'confirmed' then
        raise exception 'user is already attending this event';
    end if;

    if v_attendee_status = 'invitation-rejected' then
        raise exception 'user rejected an invitation for this event';
    end if;

    -- Enforce event capacity against already accepted attendees
    if v_capacity is not null then
        select get_event_occupied_seat_count(p_event_id) into v_attendee_count;

        if v_attendee_count >= v_capacity then
            raise exception 'event has reached capacity';
        end if;
    end if;

    -- Mark the request accepted
    update event_invitation_request
    set
        reviewed_at = current_timestamp,
        reviewed_by = p_actor_user_id,
        status = 'accepted'
    where event_id = p_event_id
    and user_id = p_user_id
    and status = 'pending';

    -- Add the confirmed attendee
    -- The conflict branch reuses pending or canceled manual invitation rows
    -- because event_attendee is keyed by event and user.
    insert into event_attendee (event_id, user_id, registration_answers)
    values (p_event_id, p_user_id, v_registration_answers)
    on conflict (event_id, user_id) do update
    set
        registration_answers = v_registration_answers,
        status = 'confirmed'
    where event_attendee.status in (
        'invitation-canceled',
        'invitation-pending',
        'registration-questions-pending'
    );

    if not found then
        raise exception 'user is not eligible to attend this event';
    end if;

    -- Track the organizer decision
    perform insert_audit_log(
        'event_invitation_request_accepted',
        p_actor_user_id,
        'user',
        p_user_id,
        v_alliance_id,
        p_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_user_id)
    );
end;
$$ language plpgsql;
