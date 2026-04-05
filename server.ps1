param(
  [int]$Port = 3000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:PublicFiles = @{
  "/" = "index.html"
  "/index.html" = "index.html"
  "/styles.css" = "styles.css"
  "/app.js" = "app.js"
}
$script:TransferCache = $null
$script:TransferCacheFetchedAt = $null
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
  "blackburn" = "Blackburn Rovers"
  "blackburn rovers" = "Blackburn Rovers"
  "blackburn rovers fc" = "Blackburn Rovers"
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

function Get-EnvFileValues {
  $envPath = Join-Path $script:ProjectRoot ".env.local"

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
    if ($pair.Count -ne 2) {
      continue
    }

    $key = $pair[0].Trim()
    $value = $pair[1].Trim().Trim('"')
    $values[$key] = $value
  }

  return $values
}

function Get-ApiToken {
  if ($env:FOOTBALL_DATA_API_TOKEN) {
    return $env:FOOTBALL_DATA_API_TOKEN
  }

  $envFile = Get-EnvFileValues
  if ($envFile.ContainsKey("FOOTBALL_DATA_API_TOKEN")) {
    return $envFile["FOOTBALL_DATA_API_TOKEN"]
  }

  throw "Fant ikke FOOTBALL_DATA_API_TOKEN. Legg tokenet i .env.local eller som miljo-variabel."
}

function Send-Response {
  param(
    [Parameter(Mandatory = $true)]$Stream,
    [Parameter(Mandatory = $true)][int]$StatusCode,
    [Parameter(Mandatory = $true)][string]$StatusText,
    [Parameter(Mandatory = $true)][string]$ContentType,
    [Parameter(Mandatory = $true)][byte[]]$BodyBytes
  )

  $headerText = @(
    "HTTP/1.1 $StatusCode $StatusText"
    "Content-Type: $ContentType"
    "Content-Length: $($BodyBytes.Length)"
    "Connection: close"
    ""
    ""
  ) -join "`r`n"

  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headerText)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  $Stream.Write($BodyBytes, 0, $BodyBytes.Length)
  $Stream.Flush()
}

function Send-JsonResponse {
  param(
    [Parameter(Mandatory = $true)]$Stream,
    [Parameter(Mandatory = $true)][int]$StatusCode,
    [Parameter(Mandatory = $true)][string]$StatusText,
    [Parameter(Mandatory = $true)]$Body
  )

  $json = $Body | ConvertTo-Json -Depth 10
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Send-Response -Stream $Stream -StatusCode $StatusCode -StatusText $StatusText -ContentType "application/json; charset=utf-8" -BodyBytes $bytes
}

function Send-FileResponse {
  param(
    [Parameter(Mandatory = $true)]$Stream,
    [Parameter(Mandatory = $true)][string]$RelativePath
  )

  $fullPath = Join-Path $script:ProjectRoot $RelativePath

  if (-not (Test-Path -LiteralPath $fullPath)) {
    Send-JsonResponse -Stream $Stream -StatusCode 404 -StatusText "Not Found" -Body @{ error = "Fant ikke filen." }
    return
  }

  $bytes = [System.IO.File]::ReadAllBytes($fullPath)
  $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
  $contentType = switch ($extension) {
    ".html" { "text/html; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    ".js" { "application/javascript; charset=utf-8" }
    default { "application/octet-stream" }
  }

  Send-Response -Stream $Stream -StatusCode 200 -StatusText "OK" -ContentType $contentType -BodyBytes $bytes
}

function Get-QueryParams {
  param([Parameter(Mandatory = $true)][string]$QueryString)

  $result = @{}
  $trimmed = $QueryString.TrimStart("?")

  if (-not $trimmed) {
    return $result
  }

  foreach ($pair in $trimmed -split "&") {
    if (-not $pair) {
      continue
    }

    $parts = $pair -split "=", 2
    $key = [System.Uri]::UnescapeDataString($parts[0])
    $value = if ($parts.Count -eq 2) { [System.Uri]::UnescapeDataString($parts[1]) } else { "" }
    $result[$key] = $value
  }

  return $result
}

function Get-ThrottleInfo {
  param([Parameter(Mandatory = $true)]$Headers)

  $requestsAvailable = $Headers["X-Requests-Available"]
  if (-not $requestsAvailable) {
    $requestsAvailable = $Headers["X-Requests-Available-Minute"]
  }

  return @{
    requestsAvailable = $requestsAvailable
    requestCounterReset = $Headers["X-RequestCounter-Reset"]
  }
}

function Get-TransferRows {
  $cacheValid = $script:TransferCache -and $script:TransferCacheFetchedAt -and ((Get-Date) - $script:TransferCacheFetchedAt).TotalMinutes -lt 30
  if ($cacheValid) {
    return $script:TransferCache
  }

  $uri = "https://raw.githubusercontent.com/ewenme/transfers/master/data/premier-league.csv"

  try {
    $csvText = Invoke-RestMethod -Uri $uri -Method Get
  } catch {
    throw [System.Exception]::new("Klarte ikke a hente overgangsdata fra GitHub-datasettet.")
  }

  $rows = $csvText | ConvertFrom-Csv
  $script:TransferCache = @($rows)
  $script:TransferCacheFetchedAt = Get-Date
  return $script:TransferCache
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

function Get-SeasonSortValue {
  param([string]$Season)

  if (-not $Season) {
    return 0
  }

  if ($Season -match "^(\d{4})/(\d{4})$") {
    return [int]$Matches[1]
  }

  return 0
}

function Get-PeriodSortValue {
  param([string]$Period)

  $normalized = ([string]$Period).Trim().ToLowerInvariant()

  return switch ($normalized) {
    "winter" { 2 }
    "summer" { 1 }
    default { 0 }
  }
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

function Search-Transfers {
  param(
    [string]$Query,
    [string]$Season
  )

  $rows = Get-DeduplicatedTransfers -Rows (Get-TransferRows)
  $normalizedQuery = if ($Query) { $Query.Trim().ToLowerInvariant() } else { "" }
  $direction = "any"
  $searchText = $normalizedQuery

  if ($normalizedQuery -match "^\s*til\s+(.+)$") {
    $direction = "to"
    $searchText = $Matches[1].Trim()
  } elseif ($normalizedQuery -match "^\s*fra\s+(.+)$") {
    $direction = "from"
    $searchText = $Matches[1].Trim()
  }

  $normalizedSearchClub = Normalize-ClubName $searchText
  $normalizedSearchClubKey = $normalizedSearchClub.ToLowerInvariant()

  $results = foreach ($item in $rows) {
    $matchesSeason = (-not $Season) -or ($item.season -eq $Season)

    if (-not $matchesSeason) {
      continue
    }

    if (-not $searchText) {
      $item
      continue
    }

    $player = ([string]$item.playerName).ToLowerInvariant()
    $fromClub = ([string]$item.fromClub).ToLowerInvariant()
    $toClub = ([string]$item.toClub).ToLowerInvariant()

    $matched = switch ($direction) {
      "to" { ($toClub -like "*$searchText*") -or ($toClub -eq $normalizedSearchClubKey) }
      "from" { ($fromClub -like "*$searchText*") -or ($fromClub -eq $normalizedSearchClubKey) }
      default {
        ($player -like "*$searchText*") -or
        ($fromClub -like "*$searchText*") -or
        ($toClub -like "*$searchText*") -or
        ($fromClub -eq $normalizedSearchClubKey) -or
        ($toClub -eq $normalizedSearchClubKey)
      }
    }

    if ($matched) {
      $item
    }
  }

  $ordered = $results |
    Sort-Object `
      @{ Expression = { Get-SeasonSortValue $_.season }; Descending = $true }, `
      @{ Expression = { Get-PeriodSortValue $_.period }; Descending = $true }, `
      @{ Expression = { [int]$_.year }; Descending = $true }, `
      @{ Expression = { $_.playerName } }

  return @($ordered | Select-Object -First 100)
}

function Get-StandingsData {
  param([int]$Season)

  $token = Get-ApiToken
  $uri = "https://api.football-data.org/v4/competitions/PL/standings?season=$Season"

  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Headers @{ "X-Auth-Token" = $token } -Method Get
  } catch {
    $exception = $_.Exception
    $statusCode = 502

    $responseProperty = $exception.PSObject.Properties["Response"]
    if ($responseProperty -and $responseProperty.Value -and $responseProperty.Value.StatusCode) {
      $statusCode = [int]$responseProperty.Value.StatusCode
    }

    $message = switch ($statusCode) {
      401 { "API-token ble avvist av football-data.org." }
      403 { "API-token mangler tilgang til denne ressursen." }
      429 { "Rate limit nadd hos football-data.org. Vent litt for nytt forsok." }
      default { "Klarte ikke a hente standings fra football-data.org." }
    }

    throw [System.Exception]::new($message)
  }

  $payload = $response.Content | ConvertFrom-Json
  $standings = @($payload.standings)
  $tableBlock = $standings | Where-Object { $_.type -eq "TOTAL" } | Select-Object -First 1

  if (-not $tableBlock) {
    $tableBlock = $standings | Select-Object -First 1
  }

  $table = @()
  if ($tableBlock -and $tableBlock.table) {
    foreach ($entry in $tableBlock.table) {
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
  }

  return @{
    competition = $payload.competition.name
    season = $Season
    lastUpdated = $response.Headers["Date"]
    table = $table
    throttle = Get-ThrottleInfo -Headers $response.Headers
  }
}

function Handle-ApiRequest {
  param(
    [Parameter(Mandatory = $true)]$Stream,
    [Parameter(Mandatory = $true)][string]$Target
  )

  $uri = [System.Uri]::new("http://localhost:$Port$Target")
  $query = Get-QueryParams -QueryString $uri.Query
  $season = 2025

  if ($query.ContainsKey("season")) {
    [void][int]::TryParse($query["season"], [ref]$season)
  }

  if ($season -lt 2020) {
    Send-JsonResponse -Stream $Stream -StatusCode 400 -StatusText "Bad Request" -Body @{ error = "Ugyldig sesong oppgitt." }
    return
  }

  try {
    $data = Get-StandingsData -Season $season
    Send-JsonResponse -Stream $Stream -StatusCode 200 -StatusText "OK" -Body $data
  } catch {
    Send-JsonResponse -Stream $Stream -StatusCode 502 -StatusText "Bad Gateway" -Body @{ error = $_.Exception.Message }
  }
}

function Handle-TransfersRequest {
  param(
    [Parameter(Mandatory = $true)]$Stream,
    [Parameter(Mandatory = $true)][string]$Target
  )

  $uri = [System.Uri]::new("http://localhost:$Port$Target")
  $query = Get-QueryParams -QueryString $uri.Query
  $search = if ($query.ContainsKey("q")) { [string]$query["q"] } else { "" }
  $season = if ($query.ContainsKey("season")) { [string]$query["season"] } else { "" }

  try {
    $results = Search-Transfers -Query $search -Season $season
    Send-JsonResponse -Stream $Stream -StatusCode 200 -StatusText "OK" -Body @{
      query = $search
      season = $season
      count = @($results).Count
      results = @($results)
      source = "https://github.com/ewenme/transfers"
      fetchedAt = (Get-Date).ToString("o")
    }
  } catch {
    Send-JsonResponse -Stream $Stream -StatusCode 502 -StatusText "Bad Gateway" -Body @{ error = $_.Exception.Message }
  }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()

Write-Host "Server kjorer pa http://localhost:$Port"
Write-Host "Trykk Ctrl+C for a stoppe."

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()

    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $requestLine = $reader.ReadLine()

      if ([string]::IsNullOrWhiteSpace($requestLine)) {
        continue
      }

      while ($true) {
        $headerLine = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($headerLine)) {
          break
        }
      }

      $parts = $requestLine -split " "
      if ($parts.Count -lt 2) {
        Send-JsonResponse -Stream $stream -StatusCode 400 -StatusText "Bad Request" -Body @{ error = "Ugyldig HTTP-foresporsel." }
        continue
      }

      $method = $parts[0].ToUpperInvariant()
      $target = $parts[1]
      $path = ([System.Uri]::new("http://localhost:$Port$target")).AbsolutePath

      if ($method -ne "GET") {
        Send-JsonResponse -Stream $stream -StatusCode 405 -StatusText "Method Not Allowed" -Body @{ error = "Kun GET er stottet." }
        continue
      }

      if ($path -eq "/api/standings") {
        Handle-ApiRequest -Stream $stream -Target $target
        continue
      }

      if ($path -eq "/api/transfers") {
        Handle-TransfersRequest -Stream $stream -Target $target
        continue
      }

      if ($script:PublicFiles.ContainsKey($path)) {
        Send-FileResponse -Stream $stream -RelativePath $script:PublicFiles[$path]
        continue
      }

      Send-JsonResponse -Stream $stream -StatusCode 404 -StatusText "Not Found" -Body @{ error = "Fant ikke ressursen." }
    } finally {
      if ($reader) {
        $reader.Dispose()
      }

      if ($stream) {
        $stream.Dispose()
      }

      $client.Dispose()
    }
  }
} finally {
  $listener.Stop()
}
