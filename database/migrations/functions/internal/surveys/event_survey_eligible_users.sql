-- Returns the users eligible to answer an event survey: confirmed attendees,
-- limited to checked-in attendees for any audience other than confirmed.
create or replace function event_survey_eligible_users(
    p_event_id uuid,
    p_audience text
)
returns table (user_id uuid) as $$
    select ea.user_id
    from event_attendee ea
    where ea.event_id = p_event_id
    and ea.status = 'confirmed'
    and (p_audience = 'confirmed' or ea.checked_in = true);
$$ language sql stable;
