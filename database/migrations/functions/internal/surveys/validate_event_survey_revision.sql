-- Rejects a request prepared for another revision of a survey. A missing
-- expected revision is treated as stale. Callers pass the locked survey row.
create or replace function validate_event_survey_revision(
    p_event_survey event_survey,
    p_expected_revision bigint
)
returns void as $$
begin
    -- Reject missing or stale revisions
    if p_event_survey.revision is distinct from p_expected_revision then
        raise exception 'the survey changed; review and try again' using errcode = 'OCG01';
    end if;
end;
$$ language plpgsql;
