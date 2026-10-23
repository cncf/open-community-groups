-- Deletes a survey of a group event together with its responses. The audit
-- row keeps the survey title and the number of deleted responses, but never
-- the responses themselves.
create or replace function delete_event_survey(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid
)
returns void as $$
declare
    v_event event;
    v_event_survey event_survey;
    v_responses_count bigint;
begin
    -- Lock the event, then the survey
    v_event := lock_event_for_surveys(p_group_id, p_event_id);
    v_event_survey := lock_event_survey(p_event_id, p_event_survey_id);

    -- Count the responses deleted with the survey
    select count(*)
    into v_responses_count
    from event_survey_response r
    where r.event_survey_id = p_event_survey_id;

    -- Delete the survey, cascading to its responses
    delete from event_survey
    where event_survey_id = p_event_survey_id;

    -- Track the deletion with a snapshot of the survey
    perform insert_audit_log(
        'event_survey_deleted',
        p_actor_user_id,
        'event_survey',
        p_event_survey_id,
        p_group_id => v_event.group_id,
        p_event_id => p_event_id,
        p_details => jsonb_build_object(
            'responses_count', v_responses_count,
            'title', v_event_survey.title
        )
    );
end;
$$ language plpgsql;
