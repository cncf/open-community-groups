-- Encodes a timestamp for JSON payloads as whole seconds since the Unix
-- epoch, truncating fractional seconds. Every timestamp the server reads
-- from function results uses this encoding.
create or replace function epoch_seconds(p_timestamp timestamptz)
returns bigint as $$
    select floor(extract(epoch from p_timestamp))::bigint;
$$ language sql immutable;
