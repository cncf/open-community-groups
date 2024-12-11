// Update results and results-mobile on DOM with content
export const updateResults = (content) => {
  const results = document.getElementById("results");
  results.innerHTML = content;
  const resultsMobile = document.getElementById("results-mobile");
  resultsMobile.innerHTML = content;
};

// Fetch API data for events or groups
export async function fetchData(entity, params) {
  const url = `/explore/${entity}/search?${params}`;
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Response status: ${response.status}`);
    }

    const json = await response.json();
    return json;
  } catch (error) {
    // TODO - Handle error
    console.error(error.message);
  }
}
