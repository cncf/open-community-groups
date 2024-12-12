// Load explore page from search input.
export const loadExplorePage = () => {
  const input = document.getElementById("ts_query");
  if (input.value !== "") {
    document.location.href = `/explore?ts_query=${input.value}`;
  }
};
