-- Completes a pending non-ticketed or grandfathered organizer invitation offer.
create or replace function complete_non_ticketed_event_admission_offer(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid,
    p_registration_answers jsonb default null,
    p_admission_offer_id uuid default null
)
returns boolean as $$
declare
    v_admission_offer_id uuid;
    v_group_id uuid;
    v_is_ticketed boolean;
    v_registration_answers jsonb;
    v_registration_questions jsonb;
begin
    -- Lock and validate the active event
    select
        e.group_id,
        exists (
            select 1
            from event_ticket_type ett
            where ett.event_id = e.event_id
        ),
        e.registration_questions
    into
        v_group_id,
        v_is_ticketed,
        v_registration_questions
    from event e
    join "group" g on g.group_id = e.group_id
    where e.event_id = p_event_id
    and g.community_id = p_community_id
    and g.active = true
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

    -- Lock the owned organizer invitation offer before claiming it
    select ao.admission_offer_id
    into v_admission_offer_id
    from admission_offer ao
    where ao.event_id = p_event_id
    and ao.event_ticket_type_id is null
    and ao.source = 'organizer_invitation'
    and ao.status = 'pending'
    and ao.user_id = p_user_id
    and (not v_is_ticketed or ao.legacy)
    and (
        p_admission_offer_id is null
        or ao.admission_offer_id = p_admission_offer_id
    )
    and (ao.expires_at is null or ao.expires_at > current_timestamp)
    for update of ao;

    if not found then
        return false;
    end if;

    -- Validate and retain registration answers at claim time
    if jsonb_array_length(coalesce(v_registration_questions, '[]'::jsonb)) > 0 then
        perform validate_questionnaire_answers_payload(
            v_registration_questions,
            p_registration_answers
        );
        v_registration_answers := p_registration_answers;
    end if;

    -- Complete the offer before creating active attendance
    update admission_offer
    set
        status = 'completed',
        updated_at = current_timestamp
    where admission_offer_id = v_admission_offer_id
    and status = 'pending';

    if not found then
        return false;
    end if;

    -- Convert the reservation into confirmed attendance
    insert into event_attendee (
        event_id,
        user_id,
        manually_invited,
        registration_answers,
        status
    ) values (
        p_event_id,
        p_user_id,
        true,
        v_registration_answers,
        'confirmed'
    )
    on conflict (event_id, user_id) do update
    set
        attendance_canceled_at = null,
        attendance_canceled_by_user_id = null,
        checked_in = false,
        checked_in_at = null,
        manually_invited = true,
        registration_answers = excluded.registration_answers,
        status = 'confirmed'
    where event_attendee.status in (
        'attendance-canceled',
        'invitation-canceled',
        'invitation-rejected'
    );

    if not found then
        raise exception 'user already has active attendance for this event';
    end if;

    -- Track the attendee decision after the claim succeeds
    perform insert_audit_log(
        'event_attendee_invitation_accepted',
        p_user_id,
        'user',
        p_user_id,
        p_community_id,
        v_group_id,
        p_event_id,
        jsonb_build_object('event_id', p_event_id, 'user_id', p_user_id)
    );

    return true;
end;
$$ language plpgsql;
