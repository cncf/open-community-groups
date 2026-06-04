/**
 * Loads the explore page with the search query from the text input.
 * Redirects to the explore page with the search term as a URL parameter.
 */
export const loadExplorePage = () => {
  const input = document.getElementById("ts_query");
  if (input && input.value !== "") {
    const params = new URLSearchParams({ ts_query: input.value });
    document.location.assign(`/explore?${params.toString()}`);
  }
};
