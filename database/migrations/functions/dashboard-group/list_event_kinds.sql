-- list_event_kinds returns all available event kinds.
create or replace function list_event_kinds()
returns json as $$
    select coalesce(json_agg(json_build_object(
        'event_kind_id', ek.event_kind_id,
        'display_name', ek.display_name
    ) order by ek.event_kind_id), '[]')
    from event_kind ek;
$$ language sql;