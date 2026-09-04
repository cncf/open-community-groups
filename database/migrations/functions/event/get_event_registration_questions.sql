-- Returns registration questions configured for an event.
create or replace function get_event_registration_questions(p_community_id uuid, p_event_id uuid)
returns json as $$
    select coalesce(e.registration_questions, '[]'::jsonb)::json
    from event e
    join "group" g using (group_id)
    where e.event_id = p_event_id
    and g.community_id = p_community_id;
$$ language sql;
