-- Returns the number of open surveys a user can answer and has not answered
-- yet.
-- Uses PL/pgSQL with `force_generic_plan` so each connection caches its plan
-- instead of planning the SQL-language body on every call.
create or replace function count_user_unanswered_event_surveys(p_user_id uuid)
returns int as $$
begin
    -- Count open surveys the user has not answered
    return (
        select count(*)::int
        from user_dashboard_event_surveys(p_user_id) us
        where us.state = 'open'
        and us.answered = false
    );
end;
$$ language plpgsql stable set plan_cache_mode = force_generic_plan;
