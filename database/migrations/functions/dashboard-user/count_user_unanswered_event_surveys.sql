-- Returns the number of open surveys a user can answer and has not answered
-- yet.
create or replace function count_user_unanswered_event_surveys(p_user_id uuid)
returns int as $$
    select count(*)::int
    from user_dashboard_event_surveys(p_user_id) us
    where us.state = 'open'
    and us.answered = false;
$$ language sql stable;
