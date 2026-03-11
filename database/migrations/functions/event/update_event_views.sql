-- update_event_views updates the views of the events provided.
create or replace function update_event_views(p_data jsonb)
returns void as $$
    -- Make sure only one batch of updates is processed at a time
    select pg_advisory_xact_lock(hashtextextended('ocg:update-event-views', 0));

    -- Insert or update the corresponding views counters as needed
    insert into event_views (event_id, day, total)
    select views_batch.*
    from (
        select
            (value->>0)::uuid as event_id,
            (value->>1)::date as day,
            (value->>2)::integer as total
        from jsonb_array_elements(p_data)
    ) as views_batch
    join event e on e.event_id = views_batch.event_id
    where e.deleted = false
        and (e.canceled = true or e.published = true)
    on conflict (event_id, day) do
    update set total = event_views.total + excluded.total;
$$ language sql;
