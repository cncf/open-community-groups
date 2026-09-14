//! Templates for the user dashboard invitations tab.

use askama::Template;

use crate::templates::helpers::DATE_FORMAT_2;
use crate::types::dashboard::user::invitations::{
    CommunityTeamInvitation, EventInvitation, GroupTeamInvitation,
};

// Pages templates.

/// List page showing pending invitations for the user.
#[derive(Debug, Clone, Template)]
#[template(path = "dashboard/user/invitations_list.html")]
pub(crate) struct ListPage {
    /// Pending community invitations for the current user.
    pub community_invitations: Vec<CommunityTeamInvitation>,
    /// Active event admission offers for the current user.
    pub event_invitations: Vec<EventInvitation>,
    /// Pending group invitations for the current user.
    pub group_invitations: Vec<GroupTeamInvitation>,
}
