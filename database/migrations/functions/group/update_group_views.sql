-- update_group_views updates the views of the groups provided.
create or replace function update_group_views(p_data jsonb)
returns void as $$
    -- Make sure only one batch of updates is processed at a time
    select pg_advisory_xact_lock(hashtextextended('ocg:update-group-views', 0));

    -- Insert or update the corresponding views counters as needed
    insert into group_views (group_id, day, total)
    select views_batch.*
    from (
        select
            (value->>0)::uuid as group_id,
            (value->>1)::date as day,
            (value->>2)::integer as total
        from jsonb_array_elements(p_data)
    ) as views_batch
    join "group" g on g.group_id = views_batch.group_id
    where g.active = true
        and g.deleted = false
    on conflict (group_id, day) do
    update set total = group_views.total + excluded.total;
$$ language sql;
