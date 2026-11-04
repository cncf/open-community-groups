//! Templates for dashboard pages.

/// Shared dashboard audit log templates.
pub(crate) mod audit;
/// Community dashboard templates.
pub(crate) mod community;
/// Group dashboard templates.
pub(crate) mod group;
/// Shared dashboard inbox templates.
pub(crate) mod inbox;
/// User dashboard templates.
pub(crate) mod user;

// Types.

/// Visual tone of a dashboard status badge.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BadgeTone {
    /// Failed, rejected, canceled or closed states.
    Danger,
    /// Informational states.
    Neutral,
    /// Invitations waiting for an answer.
    #[allow(
        dead_code,
        reason = "no typed status maps to it; templates pass it as a literal"
    )]
    Pending,
    /// Completed or positive states.
    Success,
    /// States that need attention.
    Warning,
}

impl BadgeTone {
    /// Returns the suffix used by the `badge-*` CSS classes.
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::Danger => "danger",
            Self::Neutral => "neutral",
            Self::Pending => "pending",
            Self::Success => "success",
            Self::Warning => "warning",
        }
    }
}

// Tests.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_badge_tone_as_str() {
        let cases = [
            ("danger", BadgeTone::Danger, "danger"),
            ("neutral", BadgeTone::Neutral, "neutral"),
            ("pending", BadgeTone::Pending, "pending"),
            ("success", BadgeTone::Success, "success"),
            ("warning", BadgeTone::Warning, "warning"),
        ];

        for (case, tone, expected) in cases {
            assert_eq!(tone.as_str(), expected, "{case}");
        }
    }
}
