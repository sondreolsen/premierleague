# Premier League-tabell

Liten nettside som henter den offisielle Premier League-tabellen fra `football-data.org` via en lokal PowerShell-proxy. API-tokenet ligger dermed på serversiden og blir ikke eksponert i frontend.

I tillegg kan siden søke i overgangsdata fra [ewenme/transfers](https://github.com/ewenme/transfers), slik at du kan finne spillere inn og ut av Premier League-klubber med fra-klubb, til-klubb og sum når den er oppgitt.

Prosjektet er også klargjort for GitHub Pages. Da bygges statiske JSON-filer via GitHub Actions, og selve nettsiden publiseres uten at tokenet eksponeres.

Hero-bildet bruker en fotballillustrasjon fra Wikimedia Commons, publisert som CC0/public domain:
https://commons.wikimedia.org/wiki/File:Soccerball.svg

## Oppsett

1. Lag en fil som heter `.env.local` i prosjektmappen.
2. Legg inn tokenet ditt slik:

```env
FOOTBALL_DATA_API_TOKEN=lim-inn-token-her
```

3. Start serveren:

```powershell
powershell -ExecutionPolicy Bypass -File .\server.ps1
```

4. Åpne [http://localhost:3000](http://localhost:3000)

## GitHub Pages

1. Gå til repoet på GitHub og legg inn en repository secret med navn `FOOTBALL_DATA_API_TOKEN`.
2. Gå til `Settings -> Pages`.
3. Sett `Source` til `GitHub Actions`.
4. Workflowen `.github/workflows/deploy-pages.yml` vil da bygge og publisere siden automatisk ved push til `main`, manuelt, og hver 6. time.

Etter publisering vil siden lese fra statiske filer i `data/` når lokal proxy ikke er tilgjengelig.

## Hva løsningen gjør

- Frontend henter `/api/standings` fra lokal server
- Frontend kan også hente `/api/transfers` for overgangssøk
- Serveren sender `X-Auth-Token` til `football-data.org`
- Tabellen kommer fra det offisielle endepunktet `v4/competitions/PL/standings`
- Overgangsdata kommer fra `data/premier-league.csv` i `ewenme/transfers`
- Rate-limit-headere leses og vises i grensesnittet
- GitHub Actions kan bygge statiske `data/standings.json` og `data/transfers.json` for GitHub Pages
