param(
  [string]$OutputDir = "data",
  [int]$StartSeason = 2020
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:ClubAliases = @{
  "spurs" = "Tottenham Hotspur"
  "tottenham" = "Tottenham Hotspur"
  "tottenham hotspur" = "Tottenham Hotspur"
  "tottenham hotspur fc" = "Tottenham Hotspur"
  "spurs u18" = "Tottenham Hotspur"
  "spurs u21" = "Tottenham Hotspur"
  "spurs u23" = "Tottenham Hotspur"
  "man utd" = "Manchester United"
  "manchester united" = "Manchester United"
  "manchester united fc" = "Manchester United"
  "man city" = "Manchester City"
  "manchester city" = "Manchester City"
  "manchester city fc" = "Manchester City"
  "man city u18" = "Manchester City"
  "man city u21" = "Manchester City"
  "man city u23" = "Manchester City"
  "arsenal fc" = "Arsenal"
  "chelsea fc" = "Chelsea"
  "charlton" = "Charlton Athletic"
  "charlton athletic" = "Charlton Athletic"
  "charlton athletic fc" = "Charlton Athletic"
  "leeds" = "Leeds United"
  "leeds united" = "Leeds United"
  "leeds united fc" = "Leeds United"
  "liverpool fc" = "Liverpool"
  "newcastle united" = "Newcastle"
  "newcastle united fc" = "Newcastle"
  "newcastle utd" = "Newcastle"
  "nottm forest" = "Nottingham Forest"
  "nott'm forest" = "Nottingham Forest"
  "wolves" = "Wolverhampton Wanderers"
  "wolverhampton" = "Wolverhampton Wanderers"
  "west ham" = "West Ham United"
  "west ham united" = "West Ham United"
  "brighton" = "Brighton & Hove Albion"
  "brighton and hove albion" = "Brighton & Hove Albion"
  "brighton & hove albion" = "Brighton & Hove Albion"
}

function Get-DefaultSeason {
  $now = Get-Date
  $year = $now.Year

  if ($now.Month -ge 7) {
    return $year
  }

  return ($year - 1)
}

function Ensure-Directory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Get-EnvFileValues {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $envPath = Join-Path $ProjectRoot ".env.local"
  if (-not (Test-Path -LiteralPath $envPath)) {
    return @{}
  }

  $values = @{}
  foreach ($line in Get-Content -LiteralPath $envPath) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#")) {
      continue
    }

    $pair = $trimmed -split "=", 2
    if ($pair.Count -eq 2) {
      $values[$pair[0].Trim()] = $pair[1].Trim().Trim('"')
    }
  }

  return $values
}

function Normalize-ClubName {
  param([string]$Name)

  if (-not $Name) {
    return ""
  }

  $trimmed = $Name.Trim()
  $normalized = $trimmed.ToLowerInvariant()
  $normalized = [System.Text.RegularExpressions.Regex]::Replace($normalized, "\s+u(18|19|21|23)$", "")
  $normalized = [System.Text.RegularExpressions.Regex]::Replace($normalized, "\s+fc$", "")
  $normalized = [System.Text.RegularExpressions.Regex]::Replace($normalized, "^afc\s+", "")
  $normalized = ($normalized -replace "\s+", " ").Trim()

  if ($script:ClubAliases.ContainsKey($normalized)) {
    return $script:ClubAliases[$normalized]
  }

  return (Get-Culture).TextInfo.ToTitleCase($normalized)
}

function Get-FeeRank {
  param([string]$Fee)

  if (-not $Fee -or $Fee -eq "-" -or $Fee -eq "?") {
    return 0
  }

  if ($Fee -match "loan|free|retired|end of loan|released") {
    return 1
  }

  return 2
}

function Convert-TransferRow {
  param([Parameter(Mandatory = $true)]$Row)

  $movement = [string]$Row.transfer_movement
  $fromClub = if ($movement -eq "in") { Normalize-ClubName $Row.club_involved_name } else { Normalize-ClubName $Row.club_name }
  $toClub = if ($movement -eq "in") { Normalize-ClubName $Row.club_name } else { Normalize-ClubName $Row.club_involved_name }

  return @{
    playerName = $Row.player_name
    fromClub = $fromClub
    toClub = $toClub
    fee = $Row.fee
    movement = $movement
    period = $Row.transfer_period
    season = $Row.season
    year = $Row.year
    position = $Row.position
  }
}

function Get-DeduplicatedTransfers {
  param([Parameter(Mandatory = $true)]$Rows)

  $deduped = @{}

  foreach ($row in $Rows) {
    $item = Convert-TransferRow -Row $row

    if (-not $item.playerName -or -not $item.fromClub -or -not $item.toClub) {
      continue
    }

    if ($item.fromClub -eq $item.toClub) {
      continue
    }

    $key = "{0}|{1}|{2}|{3}|{4}" -f $item.playerName.Trim().ToLowerInvariant(), $item.fromClub.ToLowerInvariant(), $item.toClub.ToLowerInvariant(), $item.season, $item.period

    if (-not $deduped.ContainsKey($key)) {
      $deduped[$key] = $item
      continue
    }

    $existing = $deduped[$key]
    if ((Get-FeeRank $item.fee) -gt (Get-FeeRank $existing.fee)) {
      $deduped[$key] = $item
    }
  }

  return @($deduped.Values)
}

function Get-TransferSnapshot {
  $uri = "https://raw.githubusercontent.com/ewenme/transfers/master/data/premier-league.csv"
  $csvText = Invoke-RestMethod -Uri $uri -Method Get
  $rows = $csvText | ConvertFrom-Csv

  $results = Get-DeduplicatedTransfers -Rows $rows

  return @{
    generatedAt = (Get-Date).ToString("o")
    source = "https://github.com/ewenme/transfers"
    count = @($results).Count
    results = @($results)
  }
}

function Get-StandingsSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][int]$FromSeason,
    [Parameter(Mandatory = $true)][int]$ToSeason
  )

  $seasons = @{}

  foreach ($season in $FromSeason..$ToSeason) {
    $uri = "https://api.football-data.org/v4/competitions/PL/standings?season=$season"
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers @{ "X-Auth-Token" = $Token } -Method Get
    } catch {
      Write-Warning "Hopper over sesong $season fordi API-et svarte med feil."
      continue
    }

    $payload = $response.Content | ConvertFrom-Json
    $standings = @($payload.standings)
    $tableBlock = $standings | Where-Object { $_.type -eq "TOTAL" } | Select-Object -First 1

    if (-not $tableBlock) {
      $tableBlock = $standings | Select-Object -First 1
    }

    $table = @()
    foreach ($entry in @($tableBlock.table)) {
      $name = $entry.team.shortName
      if (-not $name) {
        $name = $entry.team.name
      }

      $table += @{
        position = $entry.position
        name = $name
        playedGames = $entry.playedGames
        won = $entry.won
        draw = $entry.draw
        lost = $entry.lost
        goalsFor = $entry.goalsFor
        goalsAgainst = $entry.goalsAgainst
        goalDifference = $entry.goalDifference
        points = $entry.points
      }
    }

    $requestsAvailable = $response.Headers["X-Requests-Available-Minute"]
    if (-not $requestsAvailable) {
      $requestsAvailable = $response.Headers["X-Requests-Available"]
    }

    $seasons[[string]$season] = @{
      season = $season
      competition = $payload.competition.name
      lastUpdated = $response.Headers["Date"]
      throttle = @{
        requestsAvailable = $requestsAvailable
        requestCounterReset = $response.Headers["X-RequestCounter-Reset"]
      }
      table = $table
    }
  }

  return @{
    generatedAt = (Get-Date).ToString("o")
    source = "https://api.football-data.org/v4/competitions/PL/standings"
    seasons = $seasons
  }
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outputPath = Join-Path $projectRoot $OutputDir
Ensure-Directory -Path $outputPath

$token = $env:FOOTBALL_DATA_API_TOKEN
if (-not $token) {
  $envFileValues = Get-EnvFileValues -ProjectRoot $projectRoot
  if ($envFileValues.ContainsKey("FOOTBALL_DATA_API_TOKEN")) {
    $token = $envFileValues["FOOTBALL_DATA_API_TOKEN"]
  }
}

if (-not $token) {
  throw "FOOTBALL_DATA_API_TOKEN mangler."
}

$endSeason = Get-DefaultSeason
$effectiveStartSeason = [Math]::Min($StartSeason, $endSeason)
$standings = Get-StandingsSnapshot -Token $token -FromSeason $effectiveStartSeason -ToSeason $endSeason

if ($standings.seasons.Count -eq 0) {
  throw "Fant ingen sesonger som kunne bygges fra football-data.org med dette tokenet."
}

$transfers = Get-TransferSnapshot

$standings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputPath "standings.json") -Encoding UTF8
$transfers | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outputPath "transfers.json") -Encoding UTF8

Write-Host "Skrev standings og transfers til $outputPath"
