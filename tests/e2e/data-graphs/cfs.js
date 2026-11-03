import { queryE2eDatabase, queryScalar, sqlString, sqlUuid, sqlUuidArray } from "../database.js";

/**
 * Deletes owned session proposals and their CFS graph: session speakers, linked sessions,
 * submissions, then proposals. Submission label and rating rows cascade.
 * @param {{ proposalIds: string[] }} input - Exact proposal identifiers owned by the scenario.
 * @returns {void}
 */
export const cleanupSessionProposals = ({ proposalIds }) => {
  const ids = proposalIds.filter(Boolean);
  if (ids.length === 0) {
    return;
  }

  const proposalIdArray = sqlUuidArray(ids);
  const submissionIds = `
    select cfs_submission_id
    from cfs_submission
    where session_proposal_id = any(${proposalIdArray})
  `;

  queryE2eDatabase(`
    delete from session_speaker
    where session_id in (select session_id from session where cfs_submission_id in (${submissionIds}));
    delete from session where cfs_submission_id in (${submissionIds});
    delete from cfs_submission where session_proposal_id = any(${proposalIdArray});
    delete from session_proposal where session_proposal_id = any(${proposalIdArray});
  `);
};

/**
 * Returns the session proposal identifier for an owner and exact title.
 * @param {string} userId - Proposal owner.
 * @param {string} title - Exact proposal title.
 * @returns {string} Proposal identifier, or an empty string when absent.
 */
export const readSessionProposalId = (userId, title) =>
  queryScalar(`
    select session_proposal_id
    from session_proposal
    where user_id = ${sqlUuid(userId)}
    and title = ${sqlString(title)}
  `);

/**
 * Creates a not-reviewed CFS submission, as the public CFS submit does without labels.
 * Cleaned up with its proposal by `cleanupSessionProposals`.
 * @param {{ eventId: string, proposalId: string }} input - Event with an open CFS and proposal.
 * @returns {string} Submission identifier.
 */
export const setupCfsSubmission = ({ eventId, proposalId }) =>
  queryScalar(`
    insert into cfs_submission (event_id, session_proposal_id, status_id)
    values (${sqlUuid(eventId)}, ${sqlUuid(proposalId)}, 'not-reviewed')
    returning cfs_submission_id
  `);

/**
 * Creates a ready-for-submission session proposal, matching the dashboard form defaults.
 * @param {{
 *   description?: string,
 *   durationMinutes?: number,
 *   levelId?: string,
 *   title: string,
 *   userId: string,
 * }} input - Proposal fields.
 * @returns {{ proposalId: string, title: string, userId: string }}
 */
export const setupSessionProposal = ({
  description = "A reusable proposal created from the e2e suite.",
  durationMinutes = 45,
  levelId = "intermediate",
  title,
  userId,
}) => {
  const proposalId = queryScalar(`
    insert into session_proposal (
      description,
      duration,
      session_proposal_level_id,
      session_proposal_status_id,
      title,
      user_id
    ) values (
      ${sqlString(description)},
      make_interval(mins => ${Number(durationMinutes)}),
      ${sqlString(levelId)},
      'ready-for-submission',
      ${sqlString(title)},
      ${sqlUuid(userId)}
    )
    returning session_proposal_id
  `);

  return { proposalId, title, userId };
};
