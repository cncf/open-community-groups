-- Changes the status of a survey of a group event and increases its revision.
-- p_expected_revision must match the current revision. Actions:
--   mark-ready     Draft to ready. p_expected_effective_opens_at is the
--                  opening time the confirmation showed; it must still match
--                  the effective opening at whole seconds, or both must be in
--                  the past (opens now) or null (opens when the event ends).
--                  This catches event reschedules, which keep the revision.
--   back-to-draft  Scheduled to draft, before the opening email is processed
--                  and before any response.
--   close          Open to closed, recording the manual close.
--   reopen         Closed to open, clearing the manual close, unless the
--                  closing date has passed.
create or replace function change_event_survey_status(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_id uuid,
    p_event_survey_id uuid,
    p_expected_revision bigint,
    p_expected_effective_opens_at timestamptz,
    p_action text
)
returns void as $$
declare
    v_audit_action text;
    v_effective_opens_at timestamptz;
    v_event event;
    v_event_survey event_survey;
    v_state text;
begin
    -- Reject unsupported actions
    if p_action is null or p_action not in ('back-to-draft', 'close', 'mark-ready', 'reopen') then
        raise exception 'invalid event survey status action' using errcode = 'OCG01';
    end if;

    -- Lock the event, then the survey
    v_event := lock_event_for_surveys(p_group_id, p_event_id);
    v_event_survey := lock_event_survey(p_event_id, p_event_survey_id);

    -- Reject actions requested from a stale view
    perform validate_event_survey_revision(v_event_survey, p_expected_revision);

    -- Resolve the live state under the locks
    v_state := event_survey_state(v_event_survey, v_event);

    -- Apply the requested transition
    case p_action
        -- Mark a draft ready once its opening time and schedule are confirmed
        when 'mark-ready' then
            -- Allow only drafts to be marked ready
            if v_state <> 'draft' then
                raise exception 'only draft surveys can be marked ready' using errcode = 'OCG01';
            end if;

            -- Resolve the effective opening under the event lock
            v_effective_opens_at := event_survey_effective_opens_at(v_event_survey, v_event);

            -- Reject confirmations that showed another opening time
            if (
                date_trunc('second', v_effective_opens_at)
                    is not distinct from date_trunc('second', p_expected_effective_opens_at)
                or (
                    v_effective_opens_at <= current_timestamp
                    and p_expected_effective_opens_at <= current_timestamp
                )
            ) is not true then
                raise exception 'the survey opening time changed; review and try again'
                    using errcode = 'OCG01';
            end if;

            -- Require a schedule a ready survey can follow
            perform validate_event_survey_schedule(v_event_survey, v_event);

            -- Mark the survey ready
            update event_survey set
                revision = revision + 1,
                status = 'ready',
                updated_at = current_timestamp
            where event_survey_id = p_event_survey_id;
            v_audit_action := 'event_survey_marked_ready';

        -- Move a scheduled survey back to draft before anything was sent or answered
        when 'back-to-draft' then
            -- Allow only scheduled surveys without email or responses
            if v_state <> 'scheduled'
                or v_event_survey.first_response_at is not null
                or v_event_survey.open_notification_processed_at is not null
            then
                raise exception 'only scheduled surveys not yet sent or answered can move back to draft'
                    using errcode = 'OCG01';
            end if;

            -- Move the survey back to draft
            update event_survey set
                revision = revision + 1,
                status = 'draft',
                updated_at = current_timestamp
            where event_survey_id = p_event_survey_id;
            v_audit_action := 'event_survey_moved_to_draft';

        -- Close an open survey manually
        when 'close' then
            -- Allow only open surveys to be closed
            if v_state <> 'open' then
                raise exception 'only open surveys can be closed' using errcode = 'OCG01';
            end if;

            -- Record the manual close
            update event_survey set
                closed_at = current_timestamp,
                revision = revision + 1,
                updated_at = current_timestamp
            where event_survey_id = p_event_survey_id;
            v_audit_action := 'event_survey_closed';

        -- Reopen a closed survey whose closing date has not passed
        else
            -- Allow only closed surveys to be reopened
            if v_state <> 'closed' then
                raise exception 'only closed surveys can be reopened' using errcode = 'OCG01';
            end if;

            -- Require the closing date to be edited first when it has passed
            if v_event_survey.closes_at <= current_timestamp then
                raise exception 'the survey closing date has passed; edit it to reopen the survey'
                    using errcode = 'OCG01';
            end if;

            -- Clear the manual close
            update event_survey set
                closed_at = null,
                revision = revision + 1,
                updated_at = current_timestamp
            where event_survey_id = p_event_survey_id;
            v_audit_action := 'event_survey_reopened';
    end case;

    -- Track the status change with a snapshot of the survey title
    perform insert_audit_log(
        v_audit_action,
        p_actor_user_id,
        'event_survey',
        p_event_survey_id,
        p_group_id => v_event.group_id,
        p_event_id => p_event_id,
        p_details => jsonb_build_object('title', v_event_survey.title)
    );
end;
$$ language plpgsql;
