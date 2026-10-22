-- Returns the group team recipients summary of the community contact filters,
-- including the selected groups that contribute no matching seats.
-- Uses PL/pgSQL because filter validation raises user-facing errors.
create or replace function get_community_contact_recipients_summary(
    p_community_id uuid,
    p_filters jsonb
)
returns json as $$
begin
    -- Reject filter values outside the community
    perform validate_community_contact_filters(p_community_id, p_filters);

    -- Summarize the matching seats per group and across the community
    return (
        with
            -- Select the seats matching the filters
            seats as (
                select
                    s.group_id,
                    s.user_id
                from community_contact_team_seats(p_community_id, p_filters) s
            ),
            -- Count the matching seats of each contributing group
            group_seats as (
                select
                    g.group_id,
                    g.name,
                    gc.name as group_category_name,
                    r.name as region_name,
                    count(*)::int as seats_count
                from seats s
                join "group" g on g.group_id = s.group_id
                join group_category gc on gc.group_category_id = g.group_category_id
                left join region r on r.region_id = g.region_id
                group by g.group_id, g.name, gc.name, r.name
            ),
            -- Label each selected group that contributes no matching seats
            unmatched_groups as (
                select
                    l.group_id,
                    l.label
                from community_contact_filter_values(p_filters) f
                join community_contact_group_labels(p_community_id) l on l.group_id = any(f.group_ids)
                where not exists (
                    select 1
                    from seats s
                    where s.group_id = l.group_id
                )
            )
        -- Build the recipients summary payload
        select json_build_object(
            'groups', coalesce(
                (
                    select json_agg(
                        json_strip_nulls(json_build_object(
                            'group_category_name', gs.group_category_name,
                            'group_id', gs.group_id,
                            'name', gs.name,
                            'seats_count', gs.seats_count,

                            'region_name', gs.region_name
                        ))
                        order by gs.name, gs.group_id
                    )
                    from group_seats gs
                ),
                '[]'
            ),
            'groups_count', (select count(*)::int from group_seats),
            'people_count', (select count(distinct s.user_id)::int from seats s),
            'seats_count', (select count(*)::int from seats),
            'unmatched_groups', coalesce(
                (
                    select json_agg(
                        json_build_object(
                            'group_id', ug.group_id,
                            'label', ug.label
                        )
                        order by ug.label, ug.group_id
                    )
                    from unmatched_groups ug
                ),
                '[]'
            )
        )
    );
end;
$$ language plpgsql;
