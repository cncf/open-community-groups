-- Stores pending registration answers for a ticketed checkout.
create or replace function upsert_pending_registration_answers(
    p_event_id uuid,
    p_user_id uuid,
    p_registration_questions jsonb,
    p_registration_answers jsonb
)
returns void as $$
begin
    -- Skip events that do not require registration questions
    if jsonb_array_length(coalesce(p_registration_questions, '[]'::jsonb)) = 0 then
        return;
    end if;

    -- Validate answers before creating or refreshing the pending attendee row
    perform validate_questionnaire_answers_payload(p_registration_questions, p_registration_answers);

    -- Store the pending attendee answers without reviving unrelated attendee states
    insert into event_attendee (event_id, user_id, registration_answers, status)
    values (p_event_id, p_user_id, p_registration_answers, 'registration-questions-pending')
    on conflict (event_id, user_id) do update
    set
        attendance_canceled_at = null,
        attendance_canceled_by_user_id = null,
        registration_answers = p_registration_answers,
        status = 'registration-questions-pending'
    where event_attendee.status in (
        'attendance-canceled',
        'registration-questions-pending'
    );
end;
$$ language plpgsql;
