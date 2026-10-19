-- Adds a draft survey to a group event and returns its identifier. The event
-- is locked first, so the limit of 10 surveys per event (MAX_EVENT_SURVEYS in
-- Rust) holds under concurrent additions. The payload follows
-- validate_event_survey_payload.
create or replace function add_event_survey(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_payload jsonb
)
returns uuid as $$
declare
    v_event event;
    v_event_survey_id uuid;
    v_values record;
begin
    -- Lock the event whose surveys are managed
    v_event := lock_event_for_surveys(p_group_id, p_event_id);

    -- Enforce the per-event survey limit
    if (
        select count(*)
        from event_survey s
        where s.event_id = p_event_id
    ) >= 10 then
        raise exception 'events can have up to 10 surveys' using errcode = 'OCG01';
    end if;

    -- Validate and normalize the survey settings
    select * into v_values from validate_event_survey_payload(v_event, p_payload);

    -- Insert the survey as a draft
    insert into event_survey (
        anonymous,
        audience,
        event_id,
        questions,
        title,

        closes_at,
        created_by,
        description,
        opens_at
    ) values (
        v_values.anonymous,
        v_values.audience,
        p_event_id,
        v_values.questions,
        v_values.title,

        v_values.closes_at,
        p_actor_user_id,
        v_values.description,
        v_values.opens_at
    )
    returning event_survey_id into v_event_survey_id;

    -- Track the survey creation with a snapshot of its title
    perform insert_audit_log(
        'event_survey_added',
        p_actor_user_id,
        'event_survey',
        v_event_survey_id,
        (select g.community_id from "group" g where g.group_id = v_event.group_id),
        v_event.group_id,
        p_event_id,
        jsonb_build_object('title', v_values.title)
    );

    -- Return the new survey identifier
    return v_event_survey_id;
end;
$$ language plpgsql;
