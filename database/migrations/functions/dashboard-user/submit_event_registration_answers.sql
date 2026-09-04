-- Submits or updates registration answers for a user's event registration.
create or replace function submit_event_registration_answers(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_registration_answers jsonb
)
returns void as $$
declare
    v_event event;
    v_has_active_checkout_hold boolean;
    v_manually_invited boolean;
    v_registration_window_open boolean;
begin
    -- Load active event context before validating answer edits
    v_event := lock_active_event(p_community_id, null, p_event_id, true);

    -- Require a questionnaire before accepting answers
    if jsonb_array_length(coalesce(v_event.registration_questions, '[]'::jsonb)) = 0 then
        raise exception 'event does not have registration questions' using errcode = 'OCG01';
    end if;

    -- Resolve the public registration window before applying attendee-specific overrides
    v_registration_window_open := is_registration_window_open(
        v_event.registration_starts_at,
        v_event.registration_ends_at,
        v_event.starts_at
    );

    -- Block answer edits once the event has started
    if v_event.starts_at is not null
       and current_timestamp >= v_event.starts_at then
        raise exception 'registration answers can only be submitted before the event starts' using errcode = 'OCG01';
    end if;

    -- Validate submitted answers against the event questionnaire
    perform validate_questionnaire_answers_payload(v_event.registration_questions, p_registration_answers);

    -- Active checkout holds may finish answering questions after public registration closes
    select exists (
        select 1
        from event_purchase ep
        where ep.event_id = p_event_id
        and ep.user_id = p_actor_user_id
        and ep.status = 'pending'
        and ep.hold_expires_at > current_timestamp
    ) into v_has_active_checkout_hold;

    -- Lock the attendee row before storing answers
    select ea.manually_invited
    into v_manually_invited
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_actor_user_id
    and ea.status in ('confirmed', 'registration-questions-pending')
    for update of ea;

    -- Reject missing attendee registration rows
    if not found then
        raise exception 'event registration not found' using errcode = 'OCG01';
    end if;

    -- Only manual invitations and active checkout holds can answer outside the public window
    if not coalesce(v_manually_invited, false)
       and not v_has_active_checkout_hold
       and not v_registration_window_open then
        raise exception 'event registration is not open' using errcode = 'OCG01';
    end if;

    -- Store answers while checkout retains ownership of pending confirmation
    update event_attendee
    set registration_answers = p_registration_answers
    where event_id = p_event_id
    and user_id = p_actor_user_id
    and status in ('confirmed', 'registration-questions-pending');

    -- Track the answer submission
    perform insert_audit_log(
        'event_registration_questions_answered',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        p_community_id,
        v_event.group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_actor_user_id)
    );

end;
$$ language plpgsql;
