create table mock_interview_request (
    mock_interview_request_id uuid primary key default gen_random_uuid(),
    requester_user_id uuid not null references "user" (user_id) on delete cascade,
    practice_role text not null check (practice_role in ('interviewee', 'both', 'interviewer', 'not_interested')),
    interview_type text not null check (interview_type in ('software_engineering', 'ai_ml', 'startup_cofounder', 'product_management', 'devops_cloud', 'security', 'behavioral_hr', 'other')),
    target_company text not null check (target_company in ('remote_global', 'ai_labs_faang', 'enterprise', 'ai_startup', 'doesnt_matter')),
    seniority text not null check (seniority in ('graduate_junior', 'mid', 'senior', 'staff_plus')),
    location text not null check (location in ('aze', 'usa_canada', 'eu', 'other', 'asia')),
    availability text,
    notes text,
    status text default 'requested' not null check (status in ('requested', 'matched', 'scheduled', 'completed', 'canceled')),
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint mock_interview_request_availability_check check (availability is null or btrim(availability) <> ''),
    constraint mock_interview_request_notes_check check (notes is null or btrim(notes) <> '')
);

create index mock_interview_request_requester_user_id_idx
on mock_interview_request (requester_user_id, created_at desc);

create index mock_interview_request_status_idx
on mock_interview_request (status, interview_type, location, created_at desc);

create table mock_interview_match (
    mock_interview_match_id uuid primary key default gen_random_uuid(),
    mock_interview_request_id uuid not null unique references mock_interview_request (mock_interview_request_id) on delete cascade,
    created_by_user_id uuid not null references "user" (user_id),
    interviewer_user_id uuid references "user" (user_id) on delete set null,
    interviewee_user_id uuid references "user" (user_id) on delete set null,
    scheduled_at timestamptz,
    meeting_url text,
    status text default 'matched' not null check (status in ('matched', 'scheduled', 'completed', 'canceled')),
    internal_notes text,
    interviewer_feedback text,
    interviewee_feedback text,
    created_at timestamptz default current_timestamp not null,
    updated_at timestamptz,
    constraint mock_interview_match_meeting_url_check check (meeting_url is null or btrim(meeting_url) <> ''),
    constraint mock_interview_match_internal_notes_check check (internal_notes is null or btrim(internal_notes) <> ''),
    constraint mock_interview_match_interviewer_feedback_check check (interviewer_feedback is null or btrim(interviewer_feedback) <> ''),
    constraint mock_interview_match_interviewee_feedback_check check (interviewee_feedback is null or btrim(interviewee_feedback) <> '')
);

create index mock_interview_match_status_idx
on mock_interview_match (status, scheduled_at desc nulls last);
