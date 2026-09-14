-- Re-encodes the starts_at and ends_at of a price window or discount code as
-- epoch_seconds so stored and submitted spellings of the same instant
-- ("...Z", "...+00:00", "...+02:00") compare equal. Comparison-only projection
-- at whole seconds, like every payload timestamp comparison; sub-second-only
-- differences are intentionally not detected. Never written back.
create or replace function normalize_ticketing_schedule(p_schedule jsonb)
returns jsonb as $$
    select jsonb_strip_nulls(
        (p_schedule - 'ends_at' - 'starts_at')
        || jsonb_build_object(
            'ends_at', epoch_seconds((p_schedule->>'ends_at')::timestamptz),
            'starts_at', epoch_seconds((p_schedule->>'starts_at')::timestamptz)
        )
    );
$$ language sql stable;
