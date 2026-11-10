/** Query of the `phone` variant in styles.src.css: touch screens below md, on screen only. */
export const PHONE_MEDIA_QUERY = "screen and (width < 48rem) and (not (pointer: fine))";

/**
 * Keeps the screen on while a phone shows a scanner or a QR code.
 * The browser drops the lock when the page hides, so it is requested again on return.
 * @returns {() => void} Releases the lock. Does nothing off phones or without the API.
 */
export const holdScreenAwake = () => {
  if (!isPhoneViewport() || !navigator.wakeLock) {
    return () => {};
  }

  const query = window.matchMedia(PHONE_MEDIA_QUERY);
  let holding = false;
  let lock = null;
  let requesting = false;

  const acquire = async () => {
    if (!holding || requesting || document.visibilityState !== "visible" || (lock && !lock.released)) {
      return;
    }
    requesting = true;
    try {
      const nextLock = await navigator.wakeLock.request("screen");
      if (holding) {
        lock = nextLock;
      } else {
        await nextLock.release();
      }
    } catch {
      // Optional: a refused lock only lets the screen dim as usual.
    } finally {
      requesting = false;
    }
  };
  const start = () => {
    holding = true;
    document.addEventListener("visibilitychange", acquire);
    void acquire();
  };
  const stop = () => {
    holding = false;
    document.removeEventListener("visibilitychange", acquire);
    void lock?.release().catch(() => {});
    lock = null;
  };
  const handleQueryChange = () => (query.matches ? start() : stop());

  query.addEventListener("change", handleQueryChange);
  start();

  return () => {
    query.removeEventListener("change", handleQueryChange);
    stop();
  };
};

/**
 * Checks whether the phone layout is active.
 * @returns {boolean} True when the viewport matches the phone query.
 */
export const isPhoneViewport = () =>
  typeof window.matchMedia === "function" && window.matchMedia(PHONE_MEDIA_QUERY).matches;
