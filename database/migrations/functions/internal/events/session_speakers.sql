-- Returns the speakers of every session: its assigned speakers or, when it has
-- none, the author and co-speaker of its linked CFS session proposal. Proposal
-- speakers are never featured, and sort_order lists the author before the
-- co-speaker. Callers filter the rows by event, session or user; the body stays
-- a single inlinable query so those filters reach the underlying indexes.
create or replace function session_speakers()
returns table (
    event_id uuid,
    featured boolean,
    session_id uuid,
    sort_order int,
    user_id uuid
) as $$
    -- Speakers assigned to the session
    select
        s.event_id,
        ss.featured,
        ss.session_id,
        0,
        ss.user_id
    from session_speaker ss
    join session s on s.session_id = ss.session_id

    union all

    -- Author of the proposal linked to a session without assigned speakers
    select
        s.event_id,
        false,
        s.session_id,
        0,
        sp.user_id
    from session s
    join cfs_submission cs on cs.cfs_submission_id = s.cfs_submission_id
    join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
    where not exists (
        select 1
        from session_speaker ss
        where ss.session_id = s.session_id
    )

    union all

    -- Co-speaker of the proposal linked to a session without assigned speakers
    select
        s.event_id,
        false,
        s.session_id,
        1,
        sp.co_speaker_user_id
    from session s
    join cfs_submission cs on cs.cfs_submission_id = s.cfs_submission_id
    join session_proposal sp on sp.session_proposal_id = cs.session_proposal_id
    where sp.co_speaker_user_id is not null
    and not exists (
        select 1
        from session_speaker ss
        where ss.session_id = s.session_id
    );
$$ language sql stable;
