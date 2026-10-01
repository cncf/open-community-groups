-- Returns the context shown by the event page contact modal, or null when the
-- event does not accept inbox contact. The viewer section is included for
-- signed-in users only.
create or replace function get_inbox_contact_context(
    p_community_id uuid,
    p_event_id uuid,
    p_user_id uuid
)
returns json as $$
    select json_strip_nulls(json_build_object(
        'community_name', c.name,
        'event_id', e.event_id,
        'event_name', e.name,
        'event_slug', e.slug,
        'group_name', g.name,
        'group_slug', g.slug,

        'group_slug_pretty', g.slug_pretty,
        'viewer', case
            when p_user_id is null then null
            else json_build_object(
                'can_manage_inbox', user_has_group_permission(
                    c.community_id,
                    g.group_id,
                    p_user_id,
                    'group.inbox.write'
                ),
                'can_start_conversation', (
                    select l.can_start_conversation
                    from inbox_user_rate_limits(p_user_id, current_timestamp) l
                ),
                'is_blocked', is_inbox_user_blocked(g.group_id, p_user_id),
                'is_group_team_member', user_is_group_team_member(g.group_id, p_user_id),

                'open_inbox_conversation_id', (
                    select ic.inbox_conversation_id
                    from inbox_conversation ic
                    where ic.event_id = e.event_id
                    and ic.group_id = g.group_id
                    and ic.user_id = p_user_id
                    and ic.inbox_conversation_status_id = 'open'
                    order by ic.last_message_at desc, ic.inbox_conversation_id desc
                    limit 1
                )
            )
        end
    ))
    from resolve_inbox_contact_event(p_community_id, p_event_id) r
    join event e on e.event_id = r.event_id
    join "group" g on g.group_id = r.group_id
    join community c on c.community_id = g.community_id;
$$ language sql stable;
