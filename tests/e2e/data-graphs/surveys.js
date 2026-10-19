import { randomUUID } from "node:crypto";

import { queryE2eDatabase } from "../database.js";

/**
 * Seeded surveys of the past analytics event from database/tests/data/e2e/66_event_surveys.sql.
 * Its two attendees checked in. The open survey has one eligible respondent plus a response from a
 * user who never attended; both attendees answered the closed survey. Never mutate these rows.
 */
export const TEST_EVENT_ANALYTICS_SURVEYS = {
  closed: {
    id: "5c555555-5555-5555-5555-555555555962",
    title: "Analytics venue survey",
  },
  draft: {
    id: "5c555555-5555-5555-5555-555555555964",
    title: "Analytics draft survey",
  },
  open: {
    id: "5c555555-5555-5555-5555-555555555961",
    title: "Analytics session survey",
  },
  scheduled: {
    id: "5c555555-5555-5555-5555-555555555963",
    title: "Analytics follow-up survey",
  },
};

/**
 * Seeded survey event, attendees and surveys from database/tests/data/e2e/66_event_surveys.sql.
 * The event is a past test event of the alpha group, so it never sends survey emails. The first
 * member is a checked-in attendee who has not answered the open identified survey and has
 * answered the open anonymous one. Never mutate these rows.
 */
export const TEST_EVENT_SURVEYS = {
  attendeeIds: {
    checkedIn1: "77777777-7777-7777-7777-777777777971",
    checkedIn2: "77777777-7777-7777-7777-777777777972",
    notCheckedIn: "77777777-7777-7777-7777-777777777973",
  },
  event: {
    id: "55555555-5555-5555-5555-555555555971",
    name: "Survey Feedback Event",
    slug: "alpha-survey-feedback",
  },
  surveys: {
    closed: {
      id: "5c555555-5555-5555-5555-555555555975",
      questionIds: {
        impressions: "5d555555-5555-5555-5555-555555555978",
      },
      title: "Early feedback",
    },
    draft: {
      id: "5c555555-5555-5555-5555-555555555973",
      questionIds: {
        speakers: "5d555555-5555-5555-5555-555555555976",
      },
      title: "Speaker ideas",
    },
    openAnonymous: {
      id: "5c555555-5555-5555-5555-555555555972",
      optionIds: {
        no: "5e555555-5555-5555-5555-555555555978",
        yes: "5e555555-5555-5555-5555-555555555977",
      },
      questionIds: {
        comments: "5d555555-5555-5555-5555-555555555975",
        venue: "5d555555-5555-5555-5555-555555555974",
      },
      title: "Venue feedback",
    },
    openIdentified: {
      id: "5c555555-5555-5555-5555-555555555971",
      optionIds: {
        excellent: "5e555555-5555-5555-5555-555555555971",
        fair: "5e555555-5555-5555-5555-555555555973",
        good: "5e555555-5555-5555-5555-555555555972",
        kubernetes: "5e555555-5555-5555-5555-555555555974",
        observability: "5e555555-5555-5555-5555-555555555975",
        security: "5e555555-5555-5555-5555-555555555976",
      },
      questionIds: {
        improve: "5d555555-5555-5555-5555-555555555971",
        rating: "5d555555-5555-5555-5555-555555555972",
        topics: "5d555555-5555-5555-5555-555555555973",
      },
      title: "Session feedback",
    },
    scheduled: {
      id: "5c555555-5555-5555-5555-555555555974",
      questionIds: {
        again: "5d555555-5555-5555-5555-555555555977",
      },
      title: "Follow-up survey",
    },
  },
};

/**
 * Changes the revision of a survey owned by an E2E scenario, as organizer edits do, so pages
 * opened before the change submit a stale revision.
 * @param {string} surveyId - Survey owned by the scenario.
 * @returns {void}
 */
export const bumpOwnedSurveyRevision = (surveyId) => {
  queryE2eDatabase(`
    update event_survey
    set revision = revision + 1
    where event_survey_id = ${sqlString(surveyId)}::uuid;
  `);
};

/**
 * Deletes surveys owned by an E2E scenario, together with their responses.
 * @param {string[]} surveyIds - Exact survey identifiers created by the scenario.
 * @returns {void}
 */
export const cleanupEventSurveys = (surveyIds) => {
  if (surveyIds.length === 0) {
    return;
  }

  queryE2eDatabase(`
    delete from event_survey
    where event_survey_id = any(${sqlUuidArray(surveyIds)});
  `);
};

/**
 * Deletes surveys an E2E scenario created through the browser, matched by their unique title.
 * @param {{ eventId: string, title: string }} survey - Owning event and unique survey title.
 * @returns {void}
 */
export const cleanupEventSurveysByTitle = ({ eventId, title }) => {
  queryE2eDatabase(`
    delete from event_survey
    where event_id = ${sqlString(eventId)}::uuid
    and title = ${sqlString(title)};
  `);
};

/**
 * Deletes one response an E2E scenario submitted.
 * @param {{ surveyId: string, userId: string }} ids - Survey and respondent.
 * @returns {void}
 */
export const cleanupSurveyResponse = ({ surveyId, userId }) => {
  queryE2eDatabase(`
    delete from event_survey_response
    where event_survey_id = ${sqlString(surveyId)}::uuid
    and user_id = ${sqlString(userId)}::uuid;
  `);
};

/**
 * Reads the opening email marker of one survey.
 * @param {string} surveyId - Survey identifier.
 * @returns {{ processed: boolean, recipients: number|null }} Whether the email was handled and for
 * how many recipients.
 */
export const readSurveyOpenNotification = (surveyId) => {
  const [processed, recipients] = queryE2eDatabase(`
    select open_notification_processed_at is not null, open_notification_recipients
    from event_survey
    where event_survey_id = ${sqlString(surveyId)}::uuid;
  `).split("|");

  return { processed: processed === "t", recipients: recipients === "" ? null : Number(recipients) };
};

/**
 * Reads the stored answers of one survey response.
 * @param {{ surveyId: string, userId: string }} ids - Survey and respondent.
 * @returns {object|null} Stored answers payload, or null when the user has not answered.
 */
export const readSurveyResponseAnswers = ({ surveyId, userId }) => {
  const output = queryE2eDatabase(`
    select answers
    from event_survey_response
    where event_survey_id = ${sqlString(surveyId)}::uuid
    and user_id = ${sqlString(userId)}::uuid;
  `);

  return output ? JSON.parse(output) : null;
};

/**
 * Creates one survey owned by an E2E scenario. By default it has a single optional free-text
 * question; pass `questions` for other question sets. Ready surveys of ended events open
 * immediately; pass `closedAtSql` or `opensAtSql` (SQL timestamp expressions) for closed or
 * scheduled surveys; closed surveys must be ready, as drafts never close. The opening email is
 * left unprocessed so scenarios can run the producer.
 * @param {{
 *   anonymous?: boolean,
 *   audience?: "checked-in" | "confirmed",
 *   closedAtSql?: string,
 *   eventId: string,
 *   opensAtSql?: string,
 *   questions?: object[],
 *   status?: "draft" | "ready",
 *   title?: string
 * }} input - Survey fields.
 * @returns {{ id: string, questionId: string, title: string }} Survey, its first question and title.
 */
export const setupOwnedEventSurvey = ({
  anonymous = true,
  audience = "confirmed",
  closedAtSql = "null",
  eventId,
  opensAtSql = "null",
  questions,
  status = "draft",
  title,
}) => {
  if (status === "draft" && closedAtSql !== "null") {
    throw new Error("closed surveys must be ready");
  }

  const id = randomUUID();
  const surveyQuestions = questions || [
    { id: randomUUID(), kind: "free-text", options: [], prompt: "Any feedback?", required: false },
  ];
  const questionId = surveyQuestions[0].id;
  const surveyTitle = title || `E2E survey ${id.slice(0, 8)}`;

  queryE2eDatabase(`
    insert into event_survey (
      event_survey_id,
      anonymous,
      audience,
      event_id,
      questions,
      status,
      title,
      closed_at,
      opens_at
    ) values (
      ${sqlString(id)}::uuid,
      ${anonymous ? "true" : "false"},
      ${sqlString(audience)},
      ${sqlString(eventId)}::uuid,
      ${sqlString(JSON.stringify(surveyQuestions))}::jsonb,
      ${sqlString(status)},
      ${sqlString(surveyTitle)},
      ${closedAtSql},
      ${opensAtSql}
    );
  `);

  return { id, questionId, title: surveyTitle };
};

/**
 * Stores one response to a ready survey owned by an E2E scenario and locks the survey, as the
 * first response submitted from the user dashboard does.
 * @param {{ answers: object, surveyId: string, userId: string }} input - Response fields.
 * @returns {void}
 */
export const setupOwnedSurveyResponse = ({ answers, surveyId, userId }) => {
  queryE2eDatabase(`
    insert into event_survey_response (event_survey_id, user_id, answers)
    values (
      ${sqlString(surveyId)}::uuid,
      ${sqlString(userId)}::uuid,
      ${sqlString(JSON.stringify(answers))}::jsonb
    );

    update event_survey
    set first_response_at = current_timestamp
    where event_survey_id = ${sqlString(surveyId)}::uuid;
  `);
};

/** Escapes a value for embedding in E2E SQL. */
const sqlString = (value) => `'${String(value).replaceAll("'", "''")}'`;

/** Builds a UUID array literal for E2E SQL queries. */
const sqlUuidArray = (values) => `array[${values.map((value) => `${sqlString(value)}::uuid`).join(", ")}]`;
