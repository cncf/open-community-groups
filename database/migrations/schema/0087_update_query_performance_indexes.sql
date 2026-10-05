-- Add query performance indexes and drop a redundant event attendee index.

-- Bound lock waits and index builds so the migration fails instead of stalling
-- the app. Queued index locks block later queries on the same tables, and
-- plain index builds block writes while they run.
set local lock_timeout = '5s';
set local statement_timeout = '10min';

-- Index user name prefixes and the group member listing order.
create index user_member_order_idx on "user" ((name is not null) desc, lower(name), lower(username), user_id);
create index user_name_lower_pattern_idx on "user" (lower(name) text_pattern_ops);
create index user_username_lower_pattern_idx on "user" (lower(username) text_pattern_ops);

-- Collect statistics for the new user expression indexes.
analyze "user";

-- Index event purchase ticket type and discount code references.
create index event_purchase_event_discount_code_id_idx on event_purchase (event_discount_code_id)
    where event_discount_code_id is not null;
create index event_purchase_event_ticket_type_id_idx on event_purchase (event_ticket_type_id);

-- Drop the event attendee event index covered by wider indexes.
drop index event_attendee_event_id_idx;
