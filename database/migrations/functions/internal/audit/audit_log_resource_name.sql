-- Returns the current display name of an audit log resource. Deleted resources
-- fall back to the name recorded at deletion in the audit row details.
create or replace function audit_log_resource_name(
    p_resource_type text,
    p_resource_id uuid,
    p_details jsonb
)
returns text as $$
    select case p_resource_type
        when 'admission_offer' then (
            select coalesce(u.name, u.username)
            from admission_offer ao
            join "user" u on u.user_id = ao.user_id
            where ao.admission_offer_id = p_resource_id
        )
        when 'badge' then coalesce(
            (
                select b.name
                from badge b
                where b.badge_id = p_resource_id
            ),
            p_details->>'badge_name'
        )
        when 'badge_artwork' then coalesce(
            (
                select ba.file_name
                from badge_artwork ba
                where ba.badge_artwork_id = p_resource_id
            ),
            p_details->>'file_name'
        )
        when 'cfs_submission' then (
            select sp.title
            from cfs_submission cs
            join session_proposal sp using (session_proposal_id)
            where cs.cfs_submission_id = p_resource_id
        )
        when 'community' then (
            select c.display_name
            from community c
            where c.community_id = p_resource_id
        )
        when 'event' then (
            select e.name
            from event e
            where e.event_id = p_resource_id
        )
        when 'event_category' then coalesce(
            (
                select ec.name
                from event_category ec
                where ec.event_category_id = p_resource_id
            ),
            p_details->>'name'
        )
        when 'event_survey' then coalesce(
            (
                select es.title
                from event_survey es
                where es.event_survey_id = p_resource_id
            ),
            p_details->>'title'
        )
        when 'group' then (
            select g.name
            from "group" g
            where g.group_id = p_resource_id
        )
        when 'group_category' then coalesce(
            (
                select gc.name
                from group_category gc
                where gc.group_category_id = p_resource_id
            ),
            p_details->>'name'
        )
        when 'group_sponsor' then coalesce(
            (
                select gs.name
                from group_sponsor gs
                where gs.group_sponsor_id = p_resource_id
            ),
            p_details->>'name'
        )
        when 'inbox_conversation' then (
            select g.name
            from inbox_conversation ic
            join "group" g using (group_id)
            where ic.inbox_conversation_id = p_resource_id
        )
        when 'region' then coalesce(
            (
                select r.name
                from region r
                where r.region_id = p_resource_id
            ),
            p_details->>'name'
        )
        when 'session_proposal' then coalesce(
            (
                select sp.title
                from session_proposal sp
                where sp.session_proposal_id = p_resource_id
            ),
            p_details->>'title'
        )
        when 'user' then (
            select coalesce(u.name, u.username)
            from "user" u
            where u.user_id = p_resource_id
        )
        when 'user_badge' then (
            select coalesce(u.name, u.username, ub.snapshot->>'name')
            from user_badge ub
            left join "user" u on u.user_id = ub.user_id
            where ub.user_badge_id = p_resource_id
        )
    end;
$$ language sql stable;
