const CODEMIRROR_INPUT_REASON =
  "EasyMDE's CodeMirror creates its own unlabeled input textarea; naming it needs a label passed " +
  "to CodeMirror's screenReaderLabel option, which markdown-editor does not receive yet";

const USER_CHIP_INITIALS_REASON =
  "user-chip avatars render initials as text; the avatar is aria-hidden and the chip name " +
  "contains the visible user name, but axe's label-in-name check counts every visible text node";

const USER_PROFILE_TRIGGER_REASON =
  "profile modal triggers show the initials avatar and username next to the name; the button name " +
  '"View profile for <name>" contains the visible name, so speech input still works';

/**
 * Known critical or serious axe violations for `expectNoAxeViolations`. An entry matches
 * violations of `rule` in scan `scan`; `target`, a CSS selector, limits it to nodes that
 * match it or sit inside it. Each entry needs a reason, and an entry that no longer
 * matches a violation fails its scan.
 * @type {{ reason: string, rule: string, scan: string, target?: string }[]}
 */
export const AXE_ALLOWLIST = [
  {
    reason: CODEMIRROR_INPUT_REASON,
    rule: "label",
    scan: "dashboard community settings",
    target: ".CodeMirror",
  },
  {
    reason: USER_PROFILE_TRIGGER_REASON,
    rule: "label-content-name-mismatch",
    scan: "dashboard group event attendees",
    target: "[data-user-profile-modal]",
  },
  {
    reason: CODEMIRROR_INPUT_REASON,
    rule: "label",
    scan: "dashboard group event editor",
    target: ".CodeMirror",
  },
  {
    reason: USER_CHIP_INITIALS_REASON,
    rule: "label-content-name-mismatch",
    scan: "event",
    target: "user-chip",
  },
  {
    reason: USER_CHIP_INITIALS_REASON,
    rule: "label-content-name-mismatch",
    scan: "group",
    target: "user-chip",
  },
];
