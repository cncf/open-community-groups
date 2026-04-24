-- cancel_event_series_events atomically cancels events from the same series.
create or replace function cancel_event_series_events(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_ids uuid[]
)
returns void as $$
declare
    v_event_id uuid;
    v_event_ids uuid[];
begin
    -- Validate and normalize the series action ids
    v_event_ids := validate_event_series_action_event_ids(p_group_id, p_event_ids);

    -- Apply the single-event transition to each validated event
    foreach v_event_id in array v_event_ids
    loop
        perform cancel_event(p_actor_user_id, p_group_id, v_event_id);
    end loop;
end;
$$ language plpgsql;
