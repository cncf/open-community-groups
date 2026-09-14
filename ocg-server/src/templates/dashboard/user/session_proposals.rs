//! Templates for user session proposals.

use askama::Template;
use uuid::Uuid;

use crate::types::dashboard::user::session_proposals::{
    PendingCoSpeakerInvitation, SessionProposal, SessionProposalLevel,
};
use crate::{
    templates::{filters, helpers::user_initials},
    types::pagination,
};

// Pages templates.

/// List session proposals page template.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/session_proposals_list.html")]
pub(crate) struct ListPage {
    /// Current authenticated user identifier.
    pub current_user_id: Uuid,
    /// Pagination navigation links.
    pub navigation_links: pagination::NavigationLinks,
    /// Pending co-speaker invitations for this user.
    pub pending_co_speaker_invitations: Vec<PendingCoSpeakerInvitation>,
    /// Available session proposal levels.
    pub session_proposal_levels: Vec<SessionProposalLevel>,
    /// List of session proposals.
    pub session_proposals: Vec<SessionProposal>,
    /// Total number of session proposals.
    pub total: usize,

    /// Pagination offset for results.
    pub offset: Option<usize>,
}
