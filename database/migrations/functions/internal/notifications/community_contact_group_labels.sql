-- Returns the contact filter label of every group of a community, deleted
-- ones included so stale selections can still be described. Labels read
-- "<group> · <category> · <region>", without region when the group has none,
-- followed by " (<slug>)", preferring the pretty slug, when another group
-- shares that label. Deleted groups never make a non-deleted group add it.
create or replace function community_contact_group_labels(p_community_id uuid)
returns table (group_id uuid, label text) as $$
    with
        -- Build the base label of every community group
        community_groups as (
            select
                concat_ws(' · ', g.name, gc.name, r.name) as base_label,
                g.deleted,
                g.group_id,
                coalesce(g.slug_pretty, g.slug) as slug
            from "group" g
            join group_category gc on gc.group_category_id = g.group_category_id
            left join region r on r.region_id = g.region_id
            where g.community_id = p_community_id
        ),
        -- Count the groups sharing each base label, and how many are not deleted
        peers as (
            select
                cg.base_label,
                cg.deleted,
                cg.group_id,
                count(*) filter (where cg.deleted = false) over base_label_peers as non_deleted_peers_count,
                count(*) over base_label_peers as peers_count,
                cg.slug
            from community_groups cg
            window base_label_peers as (partition by cg.base_label)
        )
    -- Append the slug to groups sharing their base label
    select
        p.group_id,
        p.base_label
        || case
            when (p.deleted = false and p.non_deleted_peers_count > 1)
                or (p.deleted = true and p.peers_count > 1)
            then ' (' || p.slug || ')'
            else ''
        end as label
    from peers p;
$$ language sql stable;
