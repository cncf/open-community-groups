-- Checks whether attendees can reach a survey on the public site: the survey
-- belongs to the event and the event's group belongs to the community, the
-- community is active, the event page is public and not canceled, and the
-- survey is ready. Callers pass the rows the survey belongs to.
create or replace function is_event_survey_public(
    p_event_survey event_survey,
    p_event event,
    p_group "group",
    p_community community
)
returns boolean as $$
    select p_event_survey.event_id = p_event.event_id
        and p_event.group_id = p_group.group_id
        and p_group.community_id = p_community.community_id
        and p_community.active = true
        and is_event_public(p_event, p_group)
        and p_event.canceled = false
        and p_event_survey.status = 'ready';
$$ language sql immutable;
