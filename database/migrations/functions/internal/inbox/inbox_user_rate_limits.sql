-- Returns whether a user may start inbox conversations and send follow-up
-- messages within the rolling daily limits. Conversation starts count the
-- user's conversations and follow-ups count the user's replies created inside
-- the window; first messages and group replies never count.
create or replace function inbox_user_rate_limits(p_user_id uuid, p_now timestamptz)
returns table (can_send_follow_up boolean, can_start_conversation boolean) as $$
    with
        -- Daily limits shared by every inbox write
        limits as (
            select
                10 as max_follow_ups,
                3 as max_started_conversations,
                interval '1 day' as window_length
        )
    select
        (
            select count(*)
            from inbox_message m
            where m.author_user_id = p_user_id
            and m.kind = 'user-reply'
            and m.created_at > p_now - l.window_length
        ) < l.max_follow_ups,
        (
            select count(*)
            from inbox_conversation ic
            where ic.user_id = p_user_id
            and ic.created_at > p_now - l.window_length
        ) < l.max_started_conversations
    from limits l;
$$ language sql stable;
