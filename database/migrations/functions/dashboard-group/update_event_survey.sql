-- Updates the settings of a survey of a group event. The payload follows
-- validate_event_survey_payload and p_expected_revision must match the
-- current revision.
--
-- Once the survey has responses, its questions, audience and anonymity are
-- locked; the title, the description and the dates stay editable. Anonymous
-- surveys stay anonymous once they have opened or their opening email was
-- processed, because attendees were told their answers are anonymous;
-- identified surveys can still become anonymous until they have responses.
-- Ready surveys revalidate their schedule only when a date or the questions
-- change, so title and description fixes still work after they close. Dates
-- that match the stored ones at whole seconds keep their stored value. The
-- revision increases only when a question, the audience, the anonymity or a
-- date changes.
create or replace function update_event_survey(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid,
    p_expected_revision bigint,
    p_payload jsonb
)
returns void as $$
declare
    v_candidate event_survey;
    v_dates_changed boolean;
    v_event event;
    v_event_survey event_survey;
    v_locked_settings_changed boolean;
    v_values record;
begin
    -- Lock the event, then the survey
    v_event := lock_event_for_surveys(p_group_id, p_event_id);
    v_event_survey := lock_event_survey(p_event_id, p_event_survey_id);

    -- Reject edits made from a stale form
    perform validate_event_survey_revision(v_event_survey, p_expected_revision);

    -- Validate and normalize the survey settings
    select * into v_values from validate_event_survey_payload(v_event, p_payload);

    -- Detect changes to the settings answers depend on, and to the dates
    v_locked_settings_changed :=
        v_event_survey.anonymous is distinct from v_values.anonymous
        or v_event_survey.audience is distinct from v_values.audience
        or v_event_survey.questions is distinct from v_values.questions;
    v_dates_changed :=
        date_trunc('second', v_event_survey.closes_at) is distinct from v_values.closes_at
        or date_trunc('second', v_event_survey.opens_at) is distinct from v_values.opens_at;

    -- Keep the questions, audience and anonymity of answered surveys
    if v_event_survey.first_response_at is not null and v_locked_settings_changed then
        raise exception 'survey questions, audience and anonymity cannot change once it has responses'
            using errcode = 'OCG01';
    end if;

    -- Keep anonymous surveys anonymous once attendees may have been told so
    if v_event_survey.anonymous
        and not v_values.anonymous
        and (
            v_event_survey.open_notification_processed_at is not null
            or event_survey_state(v_event_survey, v_event) in ('closed', 'open')
        )
    then
        raise exception 'anonymity cannot be turned off after the survey has opened'
            using errcode = 'OCG01';
    end if;

    -- Revalidate the schedule of ready surveys when it or the questions change
    if v_event_survey.status = 'ready'
        and (v_dates_changed or v_event_survey.questions is distinct from v_values.questions)
    then
        -- Validate the schedule with the settings being applied
        v_candidate := v_event_survey;
        v_candidate.closes_at := v_values.closes_at;
        v_candidate.opens_at := v_values.opens_at;
        v_candidate.questions := v_values.questions;
        perform validate_event_survey_schedule(v_candidate, v_event);
    end if;

    -- Store the settings, keeping stored dates that match at whole seconds and
    -- bumping the revision on configuration changes
    update event_survey set
        anonymous = v_values.anonymous,
        audience = v_values.audience,
        closes_at = case
            -- Store the new date when a date changed
            when v_dates_changed then v_values.closes_at
            -- Keep the stored date when it matches at whole seconds
            else closes_at
        end,
        description = v_values.description,
        opens_at = case
            -- Store the new date when a date changed
            when v_dates_changed then v_values.opens_at
            -- Keep the stored date when it matches at whole seconds
            else opens_at
        end,
        questions = v_values.questions,
        revision = revision + case
            -- Bump the revision when answer-bound settings or dates change
            when v_locked_settings_changed or v_dates_changed then 1
            -- Keep the revision for title or description edits
            else 0
        end,
        title = v_values.title,
        updated_at = current_timestamp
    where event_survey_id = p_event_survey_id;

    -- Track the survey update with a snapshot of its new title
    perform insert_audit_log(
        'event_survey_updated',
        p_actor_user_id,
        'event_survey',
        p_event_survey_id,
        p_group_id => v_event.group_id,
        p_event_id => p_event_id,
        p_details => jsonb_build_object('title', v_values.title)
    );
end;
$$ language plpgsql;
