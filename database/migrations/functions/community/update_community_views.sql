-- update_community_views updates the views of the communities provided.
create or replace function update_community_views(p_data jsonb)
returns void as $$
    -- Make sure only one batch of updates is processed at a time
    select pg_advisory_xact_lock(hashtextextended('ocg:update-community-views', 0));

    -- Insert or update the corresponding views counters as needed
    insert into community_views (community_id, day, total)
    select views_batch.*
    from (
        select
            (value->>0)::uuid as community_id,
            (value->>1)::date as day,
            (value->>2)::integer as total
        from jsonb_array_elements(p_data)
    ) as views_batch
    join community c on c.community_id = views_batch.community_id
    where c.active = true
    on conflict (community_id, day) do
    update set total = community_views.total + excluded.total;
$$ language sql;
