-- update_event_views_utm updates the UTM-attributed views of the events provided.
create or replace function update_event_views_utm(p_data jsonb)
returns void as $$
    -- Make sure only one batch of updates is processed at a time
    select pg_advisory_xact_lock(hashtextextended('ocg:update-event-views-utm', 0));

    -- Insert or update the corresponding views counters as needed,
    -- pre-aggregating duplicate (event_id, day, utm) entries in the payload
    insert into event_views_utm (event_id, day, total, utm_campaign, utm_medium, utm_source)
    select
        views_batch.event_id,
        views_batch.day,
        sum(views_batch.total)::integer,
        views_batch.utm_campaign,
        views_batch.utm_medium,
        views_batch.utm_source
    from (
        select
            (value->>0)::uuid as event_id,
            (value->>1)::date as day,
            (value->>2)::text as utm_campaign,
            (value->>3)::text as utm_medium,
            (value->>4)::text as utm_source,
            (value->>5)::integer as total
        from jsonb_array_elements(p_data)
    ) as views_batch
    join event e on e.event_id = views_batch.event_id
    where e.deleted = false
        and e.published = true
    group by
        views_batch.event_id,
        views_batch.day,
        views_batch.utm_campaign,
        views_batch.utm_medium,
        views_batch.utm_source
    on conflict (event_id, day, utm_campaign, utm_medium, utm_source) do
    update set total = event_views_utm.total + excluded.total;
$$ language sql;
