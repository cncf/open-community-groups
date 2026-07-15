const SWIPE_ROOT_SELECTOR = "[data-mock-interview-swipe]";
const CARD_SELECTOR = "[data-mock-interview-swipe-card]";
const TRACK_SELECTOR = "[data-mock-interview-swipe-track]";
const PREV_SELECTOR = "[data-mock-interview-swipe-prev]";
const NEXT_SELECTOR = "[data-mock-interview-swipe-next]";
const CURRENT_SELECTOR = "[data-mock-interview-swipe-current]";
const TOTAL_SELECTOR = "[data-mock-interview-swipe-total]";
const READY_KEY = "mockInterviewSwipeReady";
const SWIPE_THRESHOLD_PX = 48;

/**
 * Reads the swipe card list for a root element.
 * @param {HTMLElement} root Swipe root
 * @returns {HTMLElement[]} Swipe cards
 */
const getCards = (root) => Array.from(root.querySelectorAll(CARD_SELECTOR));

/**
 * Updates visible card state and controls.
 * @param {HTMLElement} root Swipe root
 * @param {number} nextIndex Requested card index
 */
const setActiveCard = (root, nextIndex) => {
  const cards = getCards(root);
  if (cards.length === 0) {
    return;
  }

  const activeIndex = Math.max(0, Math.min(nextIndex, cards.length - 1));
  root.dataset.mockInterviewSwipeIndex = String(activeIndex);

  cards.forEach((card, index) => {
    const isActive = index === activeIndex;
    card.hidden = !isActive;
    card.setAttribute("aria-hidden", String(!isActive));
  });

  const current = root.querySelector(CURRENT_SELECTOR);
  if (current instanceof HTMLElement) {
    current.textContent = String(activeIndex + 1);
  }

  const total = root.querySelector(TOTAL_SELECTOR);
  if (total instanceof HTMLElement) {
    total.textContent = String(cards.length);
  }

  const prev = root.querySelector(PREV_SELECTOR);
  if (prev instanceof HTMLButtonElement) {
    prev.disabled = activeIndex === 0;
  }

  const next = root.querySelector(NEXT_SELECTOR);
  if (next instanceof HTMLButtonElement) {
    next.disabled = activeIndex === cards.length - 1;
  }
};

/**
 * Moves the active card by an offset.
 * @param {HTMLElement} root Swipe root
 * @param {number} offset Card offset
 */
const moveCard = (root, offset) => {
  const activeIndex = Number.parseInt(root.dataset.mockInterviewSwipeIndex ?? "0", 10);
  setActiveCard(root, activeIndex + offset);
};

/**
 * Initializes a single swipe deck.
 * @param {HTMLElement} root Swipe root
 */
const initSwipeRoot = (root) => {
  if (root.dataset[READY_KEY] === "true") {
    return;
  }

  root.dataset[READY_KEY] = "true";

  const cards = getCards(root);
  if (cards.length <= 1) {
    root.querySelector(PREV_SELECTOR)?.setAttribute("disabled", "");
    root.querySelector(NEXT_SELECTOR)?.setAttribute("disabled", "");
    setActiveCard(root, 0);
    return;
  }

  root.querySelector(PREV_SELECTOR)?.addEventListener("click", () => {
    moveCard(root, -1);
  });

  root.querySelector(NEXT_SELECTOR)?.addEventListener("click", () => {
    moveCard(root, 1);
  });

  const track = root.querySelector(TRACK_SELECTOR);
  if (track instanceof HTMLElement) {
    let touchStartX = 0;
    let touchStartY = 0;
    let touchMoved = false;

    track.addEventListener(
      "touchstart",
      (event) => {
        const touch = event.touches[0];
        touchStartX = touch?.clientX ?? 0;
        touchStartY = touch?.clientY ?? 0;
        touchMoved = false;
      },
      { passive: true },
    );

    track.addEventListener(
      "touchmove",
      (event) => {
        const touch = event.touches[0];
        const deltaX = Math.abs((touch?.clientX ?? 0) - touchStartX);
        const deltaY = Math.abs((touch?.clientY ?? 0) - touchStartY);
        touchMoved = deltaX > deltaY && deltaX > 12;
      },
      { passive: true },
    );

    track.addEventListener(
      "touchend",
      (event) => {
        if (!touchMoved) {
          return;
        }

        const touch = event.changedTouches[0];
        const deltaX = (touch?.clientX ?? touchStartX) - touchStartX;
        if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX) {
          return;
        }

        moveCard(root, deltaX < 0 ? 1 : -1);
      },
      { passive: true },
    );
  }

  setActiveCard(root, 0);
};

const initMockInterviewSwipes = () => {
  document.querySelectorAll(SWIPE_ROOT_SELECTOR).forEach((root) => {
    if (root instanceof HTMLElement) {
      initSwipeRoot(root);
    }
  });
};

initMockInterviewSwipes();
document.addEventListener("htmx:afterSwap", initMockInterviewSwipes);
document.addEventListener("htmx:historyRestore", initMockInterviewSwipes);
