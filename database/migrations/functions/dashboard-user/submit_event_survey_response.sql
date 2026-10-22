-- Stores or replaces a user's answers to an open survey of a public event.
-- The event is locked for share before the survey is locked for update, so
-- submissions follow the event-first lock order and serialize with organizer
-- changes. p_expected_revision must match the revision of the survey the user
-- answered. The response keeps its creation time across edits, and the first
-- response locks the survey settings through first_response_at.
create or replace function submit_event_survey_response(
    p_event_survey_id uuid,
    p_user_id uuid,
    p_expected_revision bigint,
    p_answers jsonb
)
returns void as $$
declare
    v_community community;
    v_event event;
    v_event_survey event_survey;
    v_group "group";
begin
    -- Lock the event of the survey for share before the survey
    select e.*
    into v_event
    from event e
    join event_survey s on s.event_id = e.event_id
    where s.event_survey_id = p_event_survey_id
    for share of e;

    -- Reject unknown surveys
    if not found then
        raise exception 'event survey not found' using errcode = 'OCG01';
    end if;

    -- Lock the survey, requiring it to still belong to the event
    v_event_survey := lock_event_survey(v_event.event_id, p_event_survey_id);

    -- Load the group and community the survey is published under
    select g.* into v_group from "group" g where g.group_id = v_event.group_id;
    select c.* into v_community from community c where c.community_id = v_group.community_id;

    -- Reject surveys attendees cannot reach on the public site
    if not is_event_survey_public(v_event_survey, v_event, v_group, v_community) then
        raise exception 'event survey not found' using errcode = 'OCG01';
    end if;

    -- Accept answers only while the survey is open
    if event_survey_state(v_event_survey, v_event) <> 'open' then
        raise exception 'event survey is not open' using errcode = 'OCG01';
    end if;

    -- Reject answers given to an older version of the survey
    perform validate_event_survey_revision(v_event_survey, p_expected_revision);

    -- Require the user to be in the survey audience
    if not exists (
        select 1
        from event_survey_eligible_users(v_event.event_id, v_event_survey.audience) eu
        where eu.user_id = p_user_id
    ) then
        raise exception 'you are not eligible to answer this survey' using errcode = 'OCG01';
    end if;

    -- Validate the answers against the survey questions
    perform validate_questionnaire_answers_payload(v_event_survey.questions, p_answers);

    -- Store the response, keeping its creation time when it is edited
    insert into event_survey_response (answers, event_survey_id, user_id)
    values (p_answers, p_event_survey_id, p_user_id)
    on conflict (event_survey_id, user_id) do update set
        answers = excluded.answers,
        updated_at = current_timestamp;

    -- Record the first response, which locks the survey settings
    update event_survey set
        first_response_at = current_timestamp
    where event_survey_id = p_event_survey_id
    and first_response_at is null;
end;
$$ language plpgsql;
