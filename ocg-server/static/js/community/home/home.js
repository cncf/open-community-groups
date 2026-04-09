/**
 * Loads the explore page with the search query from the text input.
 * Redirects to the explore page with the search term as a URL parameter.
 */
export const loadExplorePage = () => {
  const input = document.getElementById("ts_query");
  if (input && input.value !== "") {
    document.location.assign(`/explore?ts_query=${encodeURIComponent(input.value)}`);
  }
};
