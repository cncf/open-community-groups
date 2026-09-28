-- publish_event_series_events atomically publishes events from the same series.
create or replace function publish_event_series_events(
    p_actor_user_id uuid,
    p_group_id uuid,
    p_event_ids uuid[],
    p_configured_provider text,
    p_payment_validation jsonb default null
)
returns void as $$
declare
    v_event_id uuid;
    v_event_ids uuid[];
begin
    -- Validate and normalize the publishable series action ids
    v_event_ids := validate_event_series_action_event_ids(p_group_id, p_event_ids, true);

    -- Reject publishing the series while any occurrence has unanswered co-hosts
    if exists (
        select 1
        from unnest(v_event_ids) as selected(event_id)
        where event_has_pending_cohosts(selected.event_id)
    ) then
        raise exception 'co-hosts must respond for every event in the series before publishing' using errcode = 'OCG01';
    end if;

    -- Apply the single-event transition to each validated event
    foreach v_event_id in array v_event_ids
    loop
        perform publish_event(
            p_actor_user_id,
            p_group_id,
            v_event_id,
            p_configured_provider,
            p_payment_validation
        );
    end loop;
end;
$$ language plpgsql;
