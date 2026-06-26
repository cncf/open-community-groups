import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";

const DECK_SELECTOR = "[data-spotlight-flashcards]";
const CARD_SELECTOR = "[data-spotlight-flashcard]";
const DOT_SELECTOR = "[data-spotlight-flashcard-dot]";
const DEFAULT_INTERVAL_MS = 1500;
const initializedDecks = new WeakSet();

const prefersReducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const parseInterval = (value) => {
  const interval = Number(value);
  return Number.isFinite(interval) && interval >= 1000 ? interval : DEFAULT_INTERVAL_MS;
};

const setActiveCard = (cards, dots, activeIndex) => {
  cards.forEach((card, index) => {
    const isActive = index === activeIndex;
    card.dataset.active = isActive ? "true" : "false";
    card.setAttribute("aria-hidden", isActive ? "false" : "true");
    card.inert = !isActive;
  });

  dots.forEach((dot, index) => {
    dot.dataset.active = index === activeIndex ? "true" : "false";
  });
};

const initializeDeck = (deck) => {
  if (initializedDecks.has(deck) || !(deck instanceof HTMLElement)) {
    return;
  }
  initializedDecks.add(deck);

  const cards = Array.from(deck.querySelectorAll(CARD_SELECTOR));
  if (cards.length <= 1 || prefersReducedMotion()) {
    return;
  }

  const dots = Array.from(deck.querySelectorAll(DOT_SELECTOR));
  const intervalMs = parseInterval(deck.dataset.intervalMs);
  let activeIndex = 0;
  let intervalId = null;

  const advance = () => {
    activeIndex = (activeIndex + 1) % cards.length;
    setActiveCard(cards, dots, activeIndex);
  };

  const start = () => {
    if (intervalId === null) {
      intervalId = window.setInterval(advance, intervalMs);
    }
  };

  const stop = () => {
    if (intervalId !== null) {
      window.clearInterval(intervalId);
      intervalId = null;
    }
  };

  deck.addEventListener("mouseenter", stop);
  deck.addEventListener("mouseleave", start);
  deck.addEventListener("focusin", stop);
  deck.addEventListener("focusout", start);
  start();
};

initializeOnReadyAndHtmxLoad((root) => {
  const decks =
    root instanceof Element && root.matches(DECK_SELECTOR)
      ? [root]
      : Array.from(root.querySelectorAll(DECK_SELECTOR));

  decks.forEach(initializeDeck);
});
