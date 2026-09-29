-- Projects an inbox conversation thread with its messages. Missing users and
-- authors are emitted as JSON null, and the event is included whenever the
-- conversation still references one, flagged with whether its page is public.
create or replace function inbox_conversation_json(p_inbox_conversation_id uuid)
returns json as $$
    select (
        jsonb_strip_nulls(jsonb_build_object(
            'community_display_name', c.display_name,
            'community_name', c.name,
            'created_at', epoch_seconds(ic.created_at),
            'group_id', g.group_id,
            'group_name', g.name,
            'group_slug', g.slug,
            'inbox_conversation_id', ic.inbox_conversation_id,
            'last_message_at', epoch_seconds(ic.last_message_at),
            'status', ic.inbox_conversation_status_id,

            'event', case
                when e.event_id is null then null
                else jsonb_build_object(
                    'event_id', e.event_id,
                    'is_public', is_inbox_event_public(e, g),
                    'name', e.name,
                    'slug', e.slug
                )
            end,
            'group_slug_pretty', g.slug_pretty
        ))
        || jsonb_build_object(
            'messages', (
                select coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'body', m.body,
                            'created_at', epoch_seconds(m.created_at),
                            'inbox_message_id', m.inbox_message_id,
                            'kind', m.kind,

                            'author', case
                                when a.user_id is null then null
                                else public_user_summary(a)
                            end
                        )
                        order by m.created_at, m.inbox_message_id
                    ),
                    '[]'::jsonb
                )
                from inbox_message m
                left join "user" a on a.user_id = m.author_user_id
                where m.inbox_conversation_id = ic.inbox_conversation_id
            ),
            'user', case
                when u.user_id is null then null
                else public_user_summary(u)
            end
        )
    )::json
    from inbox_conversation ic
    join "group" g on g.group_id = ic.group_id
    join community c on c.community_id = g.community_id
    left join event e on e.event_id = ic.event_id
    left join "user" u on u.user_id = ic.user_id
    where ic.inbox_conversation_id = p_inbox_conversation_id;
$$ language sql stable;
