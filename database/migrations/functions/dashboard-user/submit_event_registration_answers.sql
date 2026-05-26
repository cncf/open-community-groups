-- Submits or updates registration answers for a user's event registration.
drop function if exists submit_event_registration_answers(uuid, uuid, uuid, jsonb);
create or replace function submit_event_registration_answers(
    p_actor_user_id uuid,
    p_community_id uuid,
    p_event_id uuid,
    p_registration_answers jsonb
)
returns boolean as $$
declare
    v_group_id uuid;
    v_has_ticket_types boolean;
    v_previous_status text;
    v_registration_questions jsonb;
    v_starts_at timestamptz;
    v_updated_status text;
begin
    -- Load active event context before validating answer edits
    select
        e.group_id,
        e.registration_questions,
        e.starts_at
    into
        v_group_id,
        v_registration_questions,
        v_starts_at
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    and g.active = true
    and e.deleted = false
    and e.published = true
    and e.canceled = false
    for update of e;

    if not found then
        raise exception 'event not found or inactive';
    end if;

    -- Require a questionnaire before accepting answers
    if jsonb_array_length(coalesce(v_registration_questions, '[]'::jsonb)) = 0 then
        raise exception 'event does not have registration questions';
    end if;

    -- Validate submitted answers against the event questionnaire
    perform validate_questionnaire_answers_payload(v_registration_questions, p_registration_answers);

    -- Ticketed registrations must be confirmed by purchase reconciliation
    select exists (
        select 1
        from event_ticket_type ett
        where ett.event_id = p_event_id
    ) into v_has_ticket_types;

    -- Lock the attendee row before applying the edit cutoff
    select ea.status
    into v_previous_status
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.user_id = p_actor_user_id
    and ea.status in ('confirmed', 'registration-questions-pending')
    for update of ea;

    if not found then
        raise exception 'event registration not found';
    end if;

    -- Block answer edits once the event has started
    if v_starts_at is not null
       and current_timestamp >= v_starts_at then
        raise exception 'registration answers can only be submitted before the event starts';
    end if;

    -- Store answers and confirm pending non-ticketed registrations
    update event_attendee
    set
        registration_answers = p_registration_answers,
        status = case
            when v_has_ticket_types and status = 'registration-questions-pending' then status
            else 'confirmed'
        end
    where event_id = p_event_id
    and user_id = p_actor_user_id
    and status in ('confirmed', 'registration-questions-pending')
    returning status into v_updated_status;

    -- Track the answer submission
    perform insert_audit_log(
        'event_registration_questions_answered',
        p_actor_user_id,
        'user',
        p_actor_user_id,
        p_community_id,
        v_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_actor_user_id)
    );

    return v_previous_status = 'registration-questions-pending'
        and v_updated_status = 'confirmed';
end;
$$ language plpgsql;
