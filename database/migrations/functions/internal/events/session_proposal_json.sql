-- Projects the session proposal fields shared by speaker and CFS listings:
-- description, duration in whole minutes, level, title and the co-speaker
-- summary (explicit null without a co-speaker; callers whose contract omits
-- nulls strip them).
create or replace function session_proposal_json(
    p_session_proposal session_proposal
)
returns jsonb as $$
    select jsonb_build_object(
        'description', p_session_proposal.description,
        'duration_minutes',
            floor(extract(epoch from p_session_proposal.duration) / 60)::int,
        'session_proposal_id', p_session_proposal.session_proposal_id,
        'session_proposal_level_id',
            p_session_proposal.session_proposal_level_id,
        'session_proposal_level_name', (
            select spl.display_name
            from session_proposal_level spl
            where spl.session_proposal_level_id
                = p_session_proposal.session_proposal_level_id
        ),
        'title', p_session_proposal.title,

        'co_speaker', (
            select public_user_summary(u)
            from "user" u
            where u.user_id = p_session_proposal.co_speaker_user_id
        )
    );
$$ language sql stable;
