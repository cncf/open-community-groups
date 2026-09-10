-- Locks an event for checkout, requiring it to be published, active and not
-- over, and returns the locked row so callers read checkout settings from it.
create or replace function prepare_event_checkout_validate_event(
    p_community_id uuid,
    p_event_id uuid
)
returns event as $$
    select lock_active_event(p_community_id, null, p_event_id, true);
$$ language sql;
