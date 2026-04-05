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
