-- Returns whether questionnaire answers have been submitted for an event.
create or replace function questionnaire_answers_exist_for_event(p_event_id uuid)
returns boolean as $$
    -- Event ids are globally unique; callers enforce alliance scope before using this lock check
    select exists (
        select 1
        from event_attendee ea
        where ea.event_id = p_event_id
        and ea.registration_answers is not null
    )
    or exists (
        select 1
        from event_invitation_request eir
        where eir.event_id = p_event_id
        and eir.registration_answers is not null
    );
$$ language sql;
