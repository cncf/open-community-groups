-- Encodes a timestamp for JSON payloads as whole seconds since the Unix
-- epoch, truncating fractional seconds. Event and enrollment timestamps read
-- by the server use this encoding; the ticketing list projections
-- (list_event_ticket_types, list_event_discount_codes) are the documented
-- exception and emit timestamptz strings.
create or replace function epoch_seconds(p_timestamp timestamptz)
returns bigint as $$
    select floor(extract(epoch from p_timestamp))::bigint;
$$ language sql immutable;
