# Premier League-tabell

Liten nettside som henter den offisielle Premier League-tabellen fra `football-data.org` via en lokal PowerShell-proxy. API-tokenet ligger dermed på serversiden og blir ikke eksponert i frontend.

I tillegg kan siden søke i overgangsdata fra [ewenme/transfers](https://github.com/ewenme/transfers), slik at du kan finne spillere inn og ut av Premier League-klubber med fra-klubb, til-klubb og sum når den er oppgitt.

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

## Hva løsningen gjør

- Frontend henter `/api/standings` fra lokal server
- Frontend kan også hente `/api/transfers` for overgangssøk
- Serveren sender `X-Auth-Token` til `football-data.org`
- Tabellen kommer fra det offisielle endepunktet `v4/competitions/PL/standings`
- Overgangsdata kommer fra `data/premier-league.csv` i `ewenme/transfers`
- Rate-limit-headere leses og vises i grensesnittet
