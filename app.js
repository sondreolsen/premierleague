const DEFAULT_SEASON = getDefaultSeason();
const CURRENT_SEASON = DEFAULT_SEASON;
const CURRENT_SEASON_LABEL = formatSeasonLabel(CURRENT_SEASON);

const tableBody = document.querySelector("#tableBody");
const tableTitle = document.querySelector("#tableTitle");
const transferQueryInput = document.querySelector("#transferQueryInput");
const transferSeasonInput = document.querySelector("#transferSeasonInput");
const transferSearchButton = document.querySelector("#transferSearchButton");
const transferTableBody = document.querySelector("#transferTableBody");
const transferSuggestions = document.querySelector("#transferSuggestions");
const transferSortButtons = [...document.querySelectorAll(".sort-button")];
const CLUB_ALIASES = {
  spurs: "tottenham hotspur",
  tottenham: "tottenham hotspur",
  "tottenham hotspur": "tottenham hotspur",
  "tottenham hotspur fc": "tottenham hotspur",
  villa: "aston villa",
  "aston villa fc": "aston villa",
  "barnsley fc": "barnsley",
  birmingham: "birmingham city",
  "birmingham city fc": "birmingham city",
  "man utd": "manchester united",
  "man united": "manchester united",
  "manchester united": "manchester united",
  "man united fc": "manchester united",
  "manchester united fc": "manchester united",
  "man city": "manchester city",
  "manchester city": "manchester city",
  "manchester city fc": "manchester city",
  "arsenal fc": "arsenal",
  bolton: "bolton wanderers",
  "bolton wanderers fc": "bolton wanderers",
  "afc bournemouth": "bournemouth",
  bradford: "bradford city",
  "bradford city afc": "bradford city",
  "brentford fc": "brentford",
  blackburn: "blackburn rovers",
  "blackburn rovers": "blackburn rovers",
  "blackburn rovers fc": "blackburn rovers",
  "blackpool fc": "blackpool",
  "brighton & hove albion fc": "brighton & hove albion",
  "burnley fc": "burnley",
  cardiff: "cardiff city",
  "cardiff city fc": "cardiff city",
  "chelsea fc": "chelsea",
  charlton: "charlton athletic",
  "charlton athletic": "charlton athletic",
  "charlton athletic fc": "charlton athletic",
  coventry: "coventry city",
  "coventry city fc": "coventry city",
  palace: "crystal palace",
  "crystal palace fc": "crystal palace",
  derby: "derby county",
  "derby county fc": "derby county",
  "everton fc": "everton",
  "fulham fc": "fulham",
  huddersfield: "huddersfield town",
  "huddersfield town afc": "huddersfield town",
  hull: "hull city",
  "hull city afc": "hull city",
  ipswich: "ipswich town",
  "ipswich town fc": "ipswich town",
  leeds: "leeds united",
  "leeds united": "leeds united",
  "leeds united fc": "leeds united",
  "leeds utd": "leeds united",
  leicester: "leicester city",
  "leicester city fc": "leicester city",
  "liverpool fc": "liverpool",
  luton: "luton town",
  "luton town fc": "luton town",
  boro: "middlesbrough",
  "middlesbrough fc": "middlesbrough",
  "newcastle united": "newcastle",
  "newcastle united fc": "newcastle",
  "newcastle utd": "newcastle",
  norwich: "norwich city",
  "norwich city fc": "norwich city",
  forest: "nottingham forest",
  wolves: "wolverhampton wanderers",
  wolverhampton: "wolverhampton wanderers",
  "wolverhampton wanderers fc": "wolverhampton wanderers",
  "west ham": "west ham united",
  "west ham utd": "west ham united",
  "west brom": "west bromwich albion",
  wba: "west bromwich albion",
  "west bromwich albion fc": "west bromwich albion",
  wigan: "wigan athletic",
  "wigan athletic fc": "wigan athletic",
  "wimbledon fc": "wimbledon",
  oldham: "oldham athletic",
  "oldham athletic afc": "oldham athletic",
  pompey: "portsmouth",
  "portsmouth fc": "portsmouth",
  qpr: "queens park rangers",
  "queens park rangers fc": "queens park rangers",
  "reading fc": "reading",
  "sheff utd": "sheffield united",
  "sheffield united fc": "sheffield united",
  "sheff wed": "sheffield wednesday",
  "sheffield wednesday fc": "sheffield wednesday",
  saints: "southampton",
  "southampton fc": "southampton",
  stoke: "stoke city",
  "stoke city fc": "stoke city",
  "sunderland afc": "sunderland",
  swansea: "swansea city",
  "swansea city afc": "swansea city",
  swindon: "swindon town",
  "swindon town fc": "swindon town",
  "watford fc": "watford",
  brighton: "brighton & hove albion",
  "brighton and hove albion": "brighton & hove albion",
  "brighton & hove albion": "brighton & hove albion"
};
let currentTransferResults = [];
let transferDataset = [];
let currentSuggestions = [];
let activeSuggestionIndex = -1;
let transferSort = {
  key: "season",
  direction: "desc"
};

tableTitle.textContent = `PL ${CURRENT_SEASON_LABEL}`;
transferSeasonInput.value = "";
updateTransferSortButtons();

transferSearchButton.addEventListener("click", () => {
  loadTransfers();
});

transferQueryInput.addEventListener("keydown", (event) => {
  if (event.key === "ArrowDown") {
    event.preventDefault();
    moveSuggestionSelection(1);
    return;
  }

  if (event.key === "ArrowUp") {
    event.preventDefault();
    moveSuggestionSelection(-1);
    return;
  }

  if (event.key === "Enter" && activeSuggestionIndex >= 0) {
    event.preventDefault();
    applySuggestion(currentSuggestions[activeSuggestionIndex]);
    loadTransfers();
    return;
  }

  if (event.key === "Escape") {
    hideTransferSuggestions();
    return;
  }

  if (event.key === "Enter") {
    loadTransfers();
  }
});

transferQueryInput.addEventListener("input", () => {
  updateTransferSuggestions();
});

transferQueryInput.addEventListener("focus", () => {
  updateTransferSuggestions();
});

transferQueryInput.addEventListener("blur", () => {
  window.setTimeout(() => {
    hideTransferSuggestions();
  }, 150);
});

transferSeasonInput.addEventListener("change", () => {
  updateTransferSuggestions();
});

for (const button of transferSortButtons) {
  button.addEventListener("click", () => {
    const { sortKey } = button.dataset;

    if (transferSort.key === sortKey) {
      transferSort.direction = transferSort.direction === "asc" ? "desc" : "asc";
    } else {
      transferSort.key = sortKey;
      transferSort.direction = sortKey === "season" ? "desc" : "asc";
    }

    updateTransferSortButtons();
    renderTransfers(currentTransferResults);
  });
}

loadTable();
loadTransferSeasonOptions();
loadTransferDataset();

async function loadTable() {
  renderEmpty("Laster tabell ...");

  try {
    const payload = await fetchStandings(CURRENT_SEASON);
    const table = payload.table;

    if (!table.length) {
      renderEmpty("Fant ingen tabell for denne sesongen.");
      return;
    }

    renderTable(table);
  } catch (error) {
    renderEmpty("Kunne ikke laste tabellen.");
  }
}

async function fetchStandings(season) {
  const liveUrl = new URL("./api/standings", window.location.href);
  liveUrl.searchParams.set("season", String(season));

  try {
    const response = await fetch(liveUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(payload.error || `Lokal server svarte med status ${response.status}.`);
    }

    payload.mode = "live";
    return payload;
  } catch {
    const snapshotUrl = new URL("./data/standings.json", window.location.href);
    const response = await fetch(snapshotUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error("Fant verken lokal server eller publisert standings-fil.");
    }

    const seasonEntry = payload.seasons?.[String(season)];
    if (!seasonEntry) {
      throw new Error(`Fant ingen publisert tabell for sesongen ${season}.`);
    }

    return {
      ...seasonEntry,
      mode: "snapshot",
      generatedAt: payload.generatedAt
    };
  }
}

async function loadTransfers() {
  const query = transferQueryInput.value.trim();
  const season = normalizeTransferSeason(transferSeasonInput.value);

  renderTransferEmpty("Laster overganger ...");
  transferSearchButton.disabled = true;

  try {
    const payload = await fetchTransfers(query, season);

    if (!payload.results.length) {
      currentTransferResults = [];
      renderTransferEmpty("Fant ingen overganger som matcher soket.");
      return;
    }

    currentTransferResults = payload.results;
    renderTransfers(currentTransferResults);
  } catch (error) {
    currentTransferResults = [];
    renderTransferEmpty("Kunne ikke laste overgangene.");
  } finally {
    transferSearchButton.disabled = false;
  }
}

async function loadTransferDataset() {
  try {
    const response = await fetch(new URL("./data/transfers.json", window.location.href));
    const payload = await response.json().catch(() => ({}));
    transferDataset = payload.results || [];
  } catch {
    transferDataset = [];
  } finally {
    updateTransferSuggestions();
  }
}

async function fetchTransfers(query, season) {
  const liveUrl = new URL("./api/transfers", window.location.href);

  if (query) {
    liveUrl.searchParams.set("q", query);
  }

  if (season) {
    liveUrl.searchParams.set("season", season);
  }

  try {
    const response = await fetch(liveUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(payload.error || `Lokal server svarte med status ${response.status}.`);
    }

    payload.mode = "live";
    return payload;
  } catch {
    const snapshotUrl = new URL("./data/transfers.json", window.location.href);
    const response = await fetch(snapshotUrl);
    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error("Fant verken lokal server eller publisert transfer-fil.");
    }

    const results = filterTransfers(payload.results || [], query, season);
    return {
      mode: "snapshot",
      count: results.length,
      results
    };
  }
}

function renderTable(table) {
  tableBody.innerHTML = table
    .map(
      (team) => `
        <tr>
          <td>${team.position}</td>
          <td>${team.name}</td>
          <td>${team.playedGames}</td>
          <td>${team.won}</td>
          <td>${team.draw}</td>
          <td>${team.lost}</td>
          <td>${team.goalsFor}</td>
          <td>${team.goalsAgainst}</td>
          <td>${formatGoalDifference(team.goalDifference)}</td>
          <td>${team.points}</td>
        </tr>
      `
    )
    .join("");
}

function renderEmpty(message) {
  tableBody.innerHTML = `<tr><td colspan="10" class="empty-state">${message}</td></tr>`;
}

function renderTransfers(results) {
  if (!results.length) {
    renderTransferEmpty("Fant ingen overganger som matcher soket.");
    return;
  }

  const sortedResults = sortTransferResults(results);

  transferTableBody.innerHTML = sortedResults
    .map(
        (item) => `
          <tr>
            <td>${item.playerName}</td>
            <td>${formatClubName(item.fromClub)}</td>
            <td>${formatClubName(item.toClub)}</td>
            <td>${formatFee(item.fee)}</td>
            <td>${item.period || "-"}</td>
            <td>${item.season || item.year || "-"}</td>
          </tr>
        `
    )
    .join("");
}

function renderTransferEmpty(message) {
  transferTableBody.innerHTML = `<tr><td colspan="6" class="empty-state">${message}</td></tr>`;
}

function formatGoalDifference(value) {
  return value > 0 ? `+${value}` : String(value);
}

function formatFee(value) {
  if (!value || value === "?" || value === "-") {
    return "Ikke oppgitt";
  }

  if (String(value).trim().toLowerCase() === "loan transfer") {
    return "Lån";
  }

  if (String(value).trim().toLowerCase() === "retired") {
    return "Lagt opp";
  }

  return value;
}

function formatClubName(value) {
  if (!value) {
    return "-";
  }

  if (String(value).trim().toLowerCase() === "without club") {
    return "Klubbløs";
  }

  return value;
}

function updateTransferSuggestions() {
  if (!transferSuggestions) {
    return;
  }

  const query = transferQueryInput.value.trim();
  const season = normalizeTransferSeason(transferSeasonInput.value);
  const normalizedQuery = query.toLowerCase();
  let direction = "";
  let searchText = normalizedQuery;

  if (normalizedQuery.startsWith("til ")) {
    direction = "til";
    searchText = normalizedQuery.slice(4).trim();
  } else if (normalizedQuery.startsWith("fra ")) {
    direction = "fra";
    searchText = normalizedQuery.slice(4).trim();
  }

  const scopedResults = filterTransfers(transferDataset, "", season);
  const suggestions = [];
  const seen = new Set();

  for (const item of scopedResults) {
    const candidates = [];
    const playerName = item.playerName || "";
    const fromClub = formatClubName(item.fromClub || "");
    const toClub = formatClubName(item.toClub || "");

    candidates.push(playerName);

    if (direction === "til") {
      candidates.push(toClub);
    } else if (direction === "fra") {
      candidates.push(fromClub);
    } else {
      candidates.push(fromClub, toClub);
    }

    for (const candidate of candidates) {
      const trimmedCandidate = candidate.trim();
      const candidateKey = trimmedCandidate.toLowerCase();

      if (!trimmedCandidate || seen.has(candidateKey)) {
        continue;
      }

      if (searchText && !candidateKey.includes(searchText)) {
        continue;
      }

      seen.add(candidateKey);
      suggestions.push(trimmedCandidate);

      if (suggestions.length >= 12) {
        renderTransferSuggestions(suggestions);
        return;
      }
    }
  }

  renderTransferSuggestions(suggestions);
}

function renderTransferSuggestions(suggestions) {
  currentSuggestions = suggestions;
  activeSuggestionIndex = -1;

  if (!suggestions.length || !transferQueryInput.value.trim()) {
    hideTransferSuggestions();
    return;
  }

  transferSuggestions.hidden = false;
  transferSuggestions.innerHTML = suggestions
    .map(
      (itemValue, index) =>
        `<button type="button" class="suggestion-item" data-suggestion-index="${index}">${escapeHtml(itemValue)}</button>`
    )
    .join("");

  for (const button of transferSuggestions.querySelectorAll(".suggestion-item")) {
    button.addEventListener("mousedown", (event) => {
      event.preventDefault();
      const index = Number(button.dataset.suggestionIndex);
      applySuggestion(currentSuggestions[index]);
      loadTransfers();
    });
  }
}

function hideTransferSuggestions() {
  currentSuggestions = [];
  activeSuggestionIndex = -1;
  transferSuggestions.hidden = true;
  transferSuggestions.innerHTML = "";
}

function moveSuggestionSelection(step) {
  if (!currentSuggestions.length) {
    updateTransferSuggestions();
  }

  if (!currentSuggestions.length) {
    return;
  }

  activeSuggestionIndex = (activeSuggestionIndex + step + currentSuggestions.length) % currentSuggestions.length;
  syncSuggestionSelection();
}

function syncSuggestionSelection() {
  const buttons = [...transferSuggestions.querySelectorAll(".suggestion-item")];

  buttons.forEach((button, index) => {
    button.classList.toggle("is-active", index === activeSuggestionIndex);
  });
}

function applySuggestion(value) {
  transferQueryInput.value = value || "";
  hideTransferSuggestions();
}

function filterTransfers(results, query, season) {
  const normalizedQuery = (query || "").trim().toLowerCase();
  const normalizedSeason = normalizeTransferSeason((season || "").trim());
  let direction = "any";
  let searchText = normalizedQuery;

  if (normalizedQuery.startsWith("til ")) {
    direction = "to";
    searchText = normalizedQuery.slice(4).trim();
  } else if (normalizedQuery.startsWith("fra ")) {
    direction = "from";
    searchText = normalizedQuery.slice(4).trim();
  }

  const normalizedSearchClub = canonicalizeClubName(searchText);

  return results
    .filter((item) => {
      if (normalizedSeason && item.season !== normalizedSeason) {
        return false;
      }

      if (!searchText) {
        return true;
      }

      const player = (item.playerName || "").toLowerCase();
      const fromClub = canonicalizeClubName(item.fromClub || "");
      const toClub = canonicalizeClubName(item.toClub || "");

      if (direction === "to") {
        return toClub.includes(searchText) || toClub === normalizedSearchClub;
      }

      if (direction === "from") {
        return fromClub.includes(searchText) || fromClub === normalizedSearchClub;
      }

      return (
        player.includes(searchText) ||
        fromClub.includes(searchText) ||
        toClub.includes(searchText) ||
        fromClub === normalizedSearchClub ||
        toClub === normalizedSearchClub
      );
    })
    .slice(0, 100);
}

function getDefaultSeason() {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();

  return month >= 6 ? year : year - 1;
}

function formatSeasonLabel(startYear) {
  const start = String(startYear).slice(-2);
  const end = String(startYear + 1).slice(-2);
  return `${start}/${end}`;
}

function normalizeTransferSeason(value) {
  if (!value) {
    return "";
  }

  const trimmed = value.trim();
  const shortMatch = trimmed.match(/^(\d{2})\s*\/\s*(\d{2})$/);
  if (shortMatch) {
    const startYear = Number.parseInt(shortMatch[1], 10);
    const fullStartYear = startYear >= 90 ? 1900 + startYear : 2000 + startYear;
    return `${fullStartYear}/${fullStartYear + 1}`;
  }

  const fullMatch = trimmed.match(/^(\d{4})\s*\/\s*(\d{4})$/);
  if (fullMatch) {
    return `${fullMatch[1]}/${fullMatch[2]}`;
  }

  return trimmed;
}

function canonicalizeClubName(value) {
  const normalized = (value || "")
    .trim()
    .toLowerCase()
    .replace(/\s+u(18|19|21|23)$/g, "")
    .replace(/\s+fc$/g, "")
    .replace(/^afc\s+/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return CLUB_ALIASES[normalized] || normalized;
}

function getSeasonSortValue(season) {
  const match = (season || "").match(/^(\d{4})\/(\d{4})$/);
  return match ? Number.parseInt(match[1], 10) : 0;
}

function getPeriodSortValue(period) {
  const normalized = (period || "").trim().toLowerCase();

  if (normalized === "winter" || normalized === "vinter") {
    return 2;
  }

  if (normalized === "summer" || normalized === "sommer") {
    return 1;
  }

  return 0;
}

async function loadTransferSeasonOptions() {
  try {
    const response = await fetch(new URL("./data/transfers.json", window.location.href));
    const payload = await response.json().catch(() => ({}));
    const seasons = [...new Set((payload.results || []).map((item) => item.season).filter(Boolean))];

    seasons.sort((a, b) => getSeasonSortValue(b) - getSeasonSortValue(a));

    transferSeasonInput.innerHTML = [
      `<option value="">Alle sesonger</option>`,
      ...seasons.map((season) => `<option value="${season}">${toShortSeasonLabel(season)}</option>`)
    ].join("");
  } catch {
    transferSeasonInput.innerHTML = `<option value="">Alle sesonger</option>`;
  }
}

function toShortSeasonLabel(season) {
  const match = (season || "").match(/^(\d{4})\/(\d{4})$/);
  if (!match) {
    return season;
  }

  return `${String(match[1]).slice(-2)}/${String(match[2]).slice(-2)}`;
}

function sortTransferResults(results) {
  const directionMultiplier = transferSort.direction === "asc" ? 1 : -1;

  return [...results].sort((a, b) => {
    const primary = compareTransferField(a, b, transferSort.key);
    if (primary !== 0) {
      return primary * directionMultiplier;
    }

    const fallbackSeason = getSeasonSortValue(b.season) - getSeasonSortValue(a.season);
    if (fallbackSeason !== 0) {
      return fallbackSeason;
    }

    const fallbackPeriod = getPeriodSortValue(b.period) - getPeriodSortValue(a.period);
    if (fallbackPeriod !== 0) {
      return fallbackPeriod;
    }

    const fallbackYear = Number.parseInt(b.year || "0", 10) - Number.parseInt(a.year || "0", 10);
    if (fallbackYear !== 0) {
      return fallbackYear;
    }

    return (a.playerName || "").localeCompare(b.playerName || "", "no");
  });
}

function compareTransferField(a, b, key) {
  if (key === "season") {
    const seasonDiff = getSeasonSortValue(a.season) - getSeasonSortValue(b.season);
    if (seasonDiff !== 0) {
      return seasonDiff;
    }

    return getPeriodSortValue(a.period) - getPeriodSortValue(b.period);
  }

  if (key === "period") {
    return getPeriodSortValue(a.period) - getPeriodSortValue(b.period);
  }

  return String(a[key] || "").localeCompare(String(b[key] || ""), "no");
}

function updateTransferSortButtons() {
  for (const button of transferSortButtons) {
    const isActive = button.dataset.sortKey === transferSort.key;
    const arrow = isActive ? (transferSort.direction === "asc" ? " ↑" : " ↓") : "";
    button.textContent = `${button.textContent.replace(/ [↑↓]$/, "")}${arrow}`;
    button.setAttribute("aria-pressed", isActive ? "true" : "false");
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
