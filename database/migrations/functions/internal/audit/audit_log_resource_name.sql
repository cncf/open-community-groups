-- Returns the current display name of an audit log resource.
create or replace function audit_log_resource_name(p_resource_type text, p_resource_id uuid)
returns text as $$
    select case p_resource_type
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
        when 'event_category' then (
            select ec.name
            from event_category ec
            where ec.event_category_id = p_resource_id
        )
        when 'group' then (
            select g.name
            from "group" g
            where g.group_id = p_resource_id
        )
        when 'group_category' then (
            select gc.name
            from group_category gc
            where gc.group_category_id = p_resource_id
        )
        when 'group_sponsor' then (
            select gs.name
            from group_sponsor gs
            where gs.group_sponsor_id = p_resource_id
        )
        when 'inbox_conversation' then (
            select g.name
            from inbox_conversation ic
            join "group" g using (group_id)
            where ic.inbox_conversation_id = p_resource_id
        )
        when 'region' then (
            select r.name
            from region r
            where r.region_id = p_resource_id
        )
        when 'session_proposal' then (
            select sp.title
            from session_proposal sp
            where sp.session_proposal_id = p_resource_id
        )
        when 'user' then (
            select coalesce(u.name, u.username)
            from "user" u
            where u.user_id = p_resource_id
        )
    end;
$$ language sql stable;
