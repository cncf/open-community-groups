/** Mocks window.print and records each print attempt made by the test subject. */
export const mockWindowPrint = () => {
  const originalPrint = window.print;
  const calls = [];

  window.print = () => {
    calls.push(true);
  };

  return {
    calls,
    restore() {
      window.print = originalPrint;
    },
  };
};
