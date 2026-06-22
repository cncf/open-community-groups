-- update_alliance_views updates the views of the alliances provided.
create or replace function update_alliance_views(p_data jsonb)
returns void as $$
    -- Make sure only one batch of updates is processed at a time
    select pg_advisory_xact_lock(hashtextextended('ocg:update-alliance-views', 0));

    -- Insert or update the corresponding views counters as needed,
    -- pre-aggregating duplicate (alliance_id, day) entries in the payload
    insert into alliance_views (alliance_id, day, total)
    select views_batch.alliance_id, views_batch.day, sum(views_batch.total)::integer
    from (
        select
            (value->>0)::uuid as alliance_id,
            (value->>1)::date as day,
            (value->>2)::integer as total
        from jsonb_array_elements(p_data)
    ) as views_batch
    join alliance c on c.alliance_id = views_batch.alliance_id
    where c.active = true
    group by views_batch.alliance_id, views_batch.day
    on conflict (alliance_id, day) do
    update set total = alliance_views.total + excluded.total;
$$ language sql;
