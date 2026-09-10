-- Inserts a baseline unpublished event row with placeholder plumbing.
create or replace function fx_event(
    p_event_id uuid,
    p_group_id uuid,
    p_event_category_id uuid,
    p_overrides jsonb default '{}'::jsonb
)
returns void as $$
begin
    perform fx_insert_row('event', jsonb_build_object(
        'description', 'Fixture event',
        'event_category_id', p_event_category_id,
        'event_id', p_event_id,
        'event_kind_id', 'in-person',
        'group_id', p_group_id,
        'name', 'Fixture Event',
        'slug', 'fixture-event-' || p_event_id,
        'timezone', 'UTC'
    ) || p_overrides);
end;
$$ language plpgsql;
