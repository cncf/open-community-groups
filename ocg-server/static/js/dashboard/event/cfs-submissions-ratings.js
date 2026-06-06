import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import {
  formatAverageRating,
  getAverageRating,
  getOtherTeamRatings,
  getRatingsCount,
} from "/static/js/dashboard/event/cfs-submissions-review-utils.js";
import "/static/js/common/rating-stars.js";

const renderStarIcon = (size = "size-5", color = "bg-amber-500") =>
  html`<div class="svg-icon ${size} icon-star ${color} shrink-0" aria-hidden="true"></div>`;

const renderRatingEditor = ({
  highlightedStars,
  ratingComment,
  ratingStars,
  messageMaxLength,
  onClearRating,
  onRatingCommentInput,
  onRatingStarEnter,
  onRatingStarSelect,
  onRatingStarsLeave,
}) => {
  const hasRating = ratingStars > 0;

  return html`
    <div>
      <label class="form-label">Your rating</label>
      <div class="mt-2 flex flex-wrap items-center gap-2" @mouseleave=${onRatingStarsLeave}>
        ${[1, 2, 3, 4, 5].map((star) => {
          const isFilled = star <= highlightedStars;
          return html`
            <button
              type="button"
              class="inline-flex items-center justify-center rounded p-0.5 transition
                hover:bg-amber-50 focus-visible:ring-2 focus-visible:ring-amber-400"
              title=${`${star} ${star === 1 ? "star" : "stars"}`}
              @click=${() => onRatingStarSelect(star)}
              @focus=${() => onRatingStarEnter(star)}
              @mouseenter=${() => onRatingStarEnter(star)}
            >
              <span class="sr-only">${star} ${star === 1 ? "star" : "stars"}</span>
              ${renderStarIcon("size-6", isFilled ? "bg-amber-500" : "bg-stone-300")}
            </button>
          `;
        })}
        <button
          type="button"
          class="btn-primary-outline btn-mini inline-flex items-center justify-center
            self-center ms-2"
          @click=${onClearRating}
          ?disabled=${!hasRating}
        >
          Clear
        </button>
        <input type="hidden" name="rating_stars" .value=${String(ratingStars)} />
      </div>
    </div>

    <div>
      <div>
        <textarea
          id="cfs-submission-rating-comment"
          name="rating_comment"
          class="input-primary"
          maxlength=${messageMaxLength}
          rows="3"
          placeholder=${hasRating ? "Add notes for other admins..." : "Select a star rating to add notes."}
          aria-label="Your rating notes"
          .value=${ratingComment}
          @input=${onRatingCommentInput}
          ?disabled=${!hasRating}
        ></textarea>
      </div>
      <p class="form-legend mt-2">Ratings are internal only. Speakers never see ratings or rating notes.</p>
    </div>
  `;
};

const renderRatingsList = ({ currentUserId, renderPersonRow, submission }) => {
  const ratings = getOtherTeamRatings(submission, currentUserId);
  if (!ratings.length) {
    return html`
      <div>
        <div class="form-label">Other team ratings</div>
        <p class="text-sm text-stone-500 mt-2">No ratings yet from other team members.</p>
      </div>
    `;
  }

  return html`
    <div>
      <div class="form-label">Other team ratings</div>
      <div class="mt-3 space-y-3">
        ${ratings.map((rating) => {
          const comments = String(rating?.comments || "").trim();
          const stars = Number(rating?.stars || 0);

          return html`
            <div class="rounded-lg border border-stone-200 bg-stone-50/50 px-4 py-3">
              <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                <div class="min-w-0 flex-1">
                  ${rating?.reviewer
                    ? renderPersonRow(rating.reviewer)
                    : html`<div class="text-sm text-stone-500">Unknown reviewer</div>`}
                  ${comments
                    ? html`<p class="mt-3 text-sm text-stone-700 whitespace-pre-line">${comments}</p>`
                    : html`<p class="mt-3 text-sm text-stone-400">No notes provided.</p>`}
                </div>
                <div class="inline-flex items-center whitespace-nowrap md:shrink-0">
                  <rating-stars .averageRating=${stars} size="size-5"></rating-stars>
                </div>
              </div>
            </div>
          `;
        })}
      </div>
    </div>
  `;
};

const renderRatingsSummaryCard = (submission) => {
  const ratingsCount = getRatingsCount(submission);
  const averageRating = getAverageRating(submission);
  const averageRatingText = formatAverageRating(averageRating);

  return html`
    <div class="rounded-lg border border-stone-200 bg-stone-50/70 px-4 py-3">
      <div class="flex flex-col gap-5 sm:flex-row sm:items-center">
        <div class="shrink-0">
          <div class="text-3xl font-semibold leading-none text-stone-800 text-center">
            ${ratingsCount > 0 ? averageRatingText : "-"}
          </div>
          <div class="text-xs text-stone-500 text-center">out of 5</div>
        </div>
        <div class="sm:border-l sm:border-stone-200 sm:pl-5 min-w-0 flex flex-col gap-1">
          <div class="form-label text-stone-700">Summary rating</div>
          <div>
            <rating-stars .averageRating=${ratingsCount > 0 ? averageRating : 0} size="size-5"></rating-stars>
          </div>
          <div class="text-sm/6 mt-1 text-stone-600">
            (${ratingsCount} ${ratingsCount === 1 ? "rating" : "ratings"})
          </div>
        </div>
      </div>
    </div>
  `;
};

/**
 * Renders the CFS review ratings panel.
 * @param {Object} state Ratings panel state and handlers.
 * @returns {import("lit").TemplateResult}
 */
export const renderCfsRatingsPanel = (state) => {
  const highlightedStars = state.hoverRatingStars || state.ratingStars;

  return html`
    <section
      id="cfs-submission-tabpanel-ratings"
      role="tabpanel"
      class="pt-5 space-y-8"
      ?hidden=${!state.isActive}
    >
      ${renderRatingsSummaryCard(state.submission)} ${renderRatingEditor({ ...state, highlightedStars })}
      ${renderRatingsList(state)}
    </section>
  `;
};
