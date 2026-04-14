-- Drop old payments and publish function signatures after adding the
-- configured provider parameter.

drop function if exists prepare_event_checkout_purchase(uuid, uuid, uuid, uuid, text);
drop function if exists prepare_event_checkout_validate_event(uuid, uuid);
drop function if exists publish_event(uuid, uuid, uuid);
