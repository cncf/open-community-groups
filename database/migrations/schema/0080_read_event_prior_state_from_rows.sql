-- Drops the event payload helpers that took the public event projection as prior state, the checkout validator that returned only the currency, and the unused stale-hold expiry helper.

drop function if exists event_ticketing_configuration_changed(jsonb, jsonb);
drop function if exists is_event_meeting_in_sync(jsonb, jsonb);
drop function if exists is_session_meeting_in_sync(jsonb, jsonb, jsonb, jsonb);
drop function if exists prepare_event_checkout_expire_stale_holds(uuid);
drop function if exists prepare_event_checkout_validate_event(uuid, uuid);
drop function if exists sync_event_sessions(uuid, jsonb, jsonb);
drop function if exists validate_update_event_dates(jsonb, jsonb);
