-- Inserts a baseline event series row with placeholder plumbing.
create or replace function fx_event_series(
    p_event_series_id uuid,
    p_group_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('event_series', jsonb_build_object(
        'event_series_id', p_event_series_id,
        'group_id', p_group_id,
        'recurrence_additional_occurrences', 1,
        'recurrence_anchor_starts_at', '2030-01-01 00:00:00+00',
        'recurrence_pattern', 'weekly',
        'timezone', 'UTC'
    ) || p_overrides);
end;
$$ language plpgsql;
