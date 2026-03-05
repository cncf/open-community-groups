//! Permission identifiers used by RBAC checks.

/// Community-scoped permission identifiers.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CommunityPermission {
    /// Permission to manage groups in a community.
    GroupsWrite,
    /// Permission to read the community dashboard.
    Read,
    /// Permission to manage community settings.
    SettingsWrite,
    /// Permission to manage community taxonomy entities.
    TaxonomyWrite,
    /// Permission to manage community team membership.
    TeamWrite,
}

impl CommunityPermission {
    /// Returns the canonical string identifier used in SQL checks.
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::GroupsWrite => "community.groups.write",
            Self::Read => "community.read",
            Self::SettingsWrite => "community.settings.write",
            Self::TaxonomyWrite => "community.taxonomy.write",
            Self::TeamWrite => "community.team.write",
        }
    }
}

impl PartialEq<CommunityPermission> for &CommunityPermission {
    fn eq(&self, other: &CommunityPermission) -> bool {
        **self == *other
    }
}

/// Group-scoped permission identifiers.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum GroupPermission {
    /// Permission to manage events in a group.
    EventsWrite,
    /// Permission to manage group members.
    MembersWrite,
    /// Permission to read the group dashboard.
    Read,
    /// Permission to manage group settings.
    SettingsWrite,
    /// Permission to manage group sponsors.
    SponsorsWrite,
    /// Permission to manage group team membership.
    TeamWrite,
}

impl GroupPermission {
    /// Returns the canonical string identifier used in SQL checks.
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::EventsWrite => "group.events.write",
            Self::MembersWrite => "group.members.write",
            Self::Read => "group.read",
            Self::SettingsWrite => "group.settings.write",
            Self::SponsorsWrite => "group.sponsors.write",
            Self::TeamWrite => "group.team.write",
        }
    }
}

impl PartialEq<GroupPermission> for &GroupPermission {
    fn eq(&self, other: &GroupPermission) -> bool {
        **self == *other
    }
}
