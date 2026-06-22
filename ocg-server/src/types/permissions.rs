//! Permission identifiers used by RBAC checks.

/// Alliance-scoped permission identifiers.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum AlliancePermission {
    /// Permission to manage groups in a alliance.
    GroupsWrite,
    /// Permission to read the alliance dashboard.
    Read,
    /// Permission to manage alliance settings.
    SettingsWrite,
    /// Permission to manage alliance taxonomy entities.
    TaxonomyWrite,
    /// Permission to manage alliance team membership.
    TeamWrite,
}

impl AlliancePermission {
    /// Returns the canonical string identifier used in SQL checks.
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::GroupsWrite => "alliance.groups.write",
            Self::Read => "alliance.read",
            Self::SettingsWrite => "alliance.settings.write",
            Self::TaxonomyWrite => "alliance.taxonomy.write",
            Self::TeamWrite => "alliance.team.write",
        }
    }
}

impl PartialEq<AlliancePermission> for &AlliancePermission {
    fn eq(&self, other: &AlliancePermission) -> bool {
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
