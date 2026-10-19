-- Returns the live state of a survey: draft, closed (manually or past its
-- closing date), scheduled (unpublished event, or opening unknown or in the
-- future) or open.
create or replace function event_survey_state(
    p_event_survey event_survey,
    p_event event
)
returns text as $$
    select case
        when p_event_survey.status = 'draft' then 'draft'
        when p_event_survey.closed_at is not null
            or p_event_survey.closes_at <= current_timestamp then 'closed'
        when p_event.published = false
            or event_survey_effective_opens_at(p_event_survey, p_event) is null
            or event_survey_effective_opens_at(p_event_survey, p_event) > current_timestamp
            then 'scheduled'
        else 'open'
    end;
$$ language sql stable;
