-- Returns a filtered page of inbox conversations for exactly one scope: a
-- group or a user. The user scope excludes conversations of deleted groups,
-- and the group scope leaves conversations marked as spam out unless the
-- status filter asks for them.
create or replace function search_inbox_conversations(
    p_group_id uuid,
    p_user_id uuid,
    p_filters jsonb
)
returns json as $$
declare
    v_limit int;
    v_offset int;
    v_result json;
    v_status text;
begin
    -- Require exactly one scope
    if (p_group_id is null) = (p_user_id is null) then
        raise exception 'exactly one inbox scope is required';
    end if;

    -- Parse pagination and status filters
    select
        coalesce(f.limit_value, 50),
        coalesce(f.offset_value, 0)
    into
        v_limit,
        v_offset
    from parse_search_filters(p_filters) f;
    v_status := nullif(btrim(p_filters->>'status'), '');

    -- Build the requested page together with the total
    with
        -- Conversations visible in the requested scope
        scoped as (
            select
                ic.created_at,
                ic.event_id,
                ic.group_id,
                ic.inbox_conversation_id,
                ic.inbox_conversation_status_id,
                ic.last_message_at,
                ic.user_id
            from inbox_conversation ic
            join "group" g on g.group_id = ic.group_id
            where (p_group_id is null or ic.group_id = p_group_id)
            and (p_user_id is null or (ic.user_id = p_user_id and g.deleted = false))
            and (
                ic.inbox_conversation_status_id = v_status
                or (
                    v_status is null
                    and (p_group_id is null or ic.inbox_conversation_status_id <> 'spam')
                )
            )
        ),
        -- Count rows before pagination
        totals as (
            select count(*)::int as total
            from scoped
        ),
        -- Select the requested page
        paged as (
            select *
            from scoped
            order by last_message_at desc, inbox_conversation_id desc
            offset v_offset
            limit v_limit
        ),
        -- Render each row with its latest message
        conversations_json as (
            select coalesce(
                json_agg(
                    (
                        jsonb_strip_nulls(jsonb_build_object(
                            'community_display_name', c.display_name,
                            'community_name', c.name,
                            'created_at', epoch_seconds(p.created_at),
                            'group_id', g.group_id,
                            'group_name', g.name,
                            'inbox_conversation_id', p.inbox_conversation_id,
                            'last_message_at', epoch_seconds(p.last_message_at),
                            'last_message_excerpt', left(lm.body, 160),
                            'last_message_kind', lm.kind,
                            'status', p.inbox_conversation_status_id,

                            'event', case
                                when e.event_id is null then null
                                else jsonb_build_object(
                                    'event_id', e.event_id,
                                    'is_public', is_inbox_event_public(e, g),
                                    'name', e.name
                                )
                            end
                        ))
                        || jsonb_build_object(
                            'user', case
                                when u.user_id is null then null
                                else public_user_summary(u)
                            end
                        )
                    )
                    order by p.last_message_at desc, p.inbox_conversation_id desc
                ),
                '[]'::json
            ) as conversations
            from paged p
            join "group" g on g.group_id = p.group_id
            join community c on c.community_id = g.community_id
            left join event e on e.event_id = p.event_id
            left join "user" u on u.user_id = p.user_id
            cross join lateral (
                select
                    m.body,
                    m.kind
                from inbox_message m
                where m.inbox_conversation_id = p.inbox_conversation_id
                order by m.created_at desc, m.inbox_message_id desc
                limit 1
            ) lm
        )
    select json_build_object(
        'conversations', conversations_json.conversations,
        'total', totals.total
    )
    into v_result
    from conversations_json, totals;

    return v_result;
end;
$$ language plpgsql stable;
