param(
  [string]$ConfigPath = ""
)

$ErrorActionPreference = "Continue"
$Version = "1.2.0"

$ConfigDir = Join-Path $env:APPDATA "openclaw-gateway-watchdog"
$StateDir = Join-Path $env:LOCALAPPDATA "openclaw-gateway-watchdog"
if (-not $ConfigPath) {
  $ConfigPath = Join-Path $ConfigDir "watchdog.json"
}

$DefaultConfig = [ordered]@{
  GatewayHealthUrl = "http://127.0.0.1:18789/healthz"
  GatewayHost = "127.0.0.1"
  GatewayPort = 18789
  ChannelUrl = "https://ilinkai.weixin.qq.com"
  NetworkUrls = @("https://www.baidu.com", "https://www.qq.com", "https://api.weixin.qq.com")
  RestartCommand = ""
  OpenClawNativeProbes = "auto"
  OpenClawHealthTimeoutMs = 12000
  OpenClawGatewayStrict = $false
  OpenClawChannelsProbe = $true
  BaseInterval = 60
  NightInterval = 300
  MaxInterval = 1800
  ConnectTimeout = 5
  MaxTime = 10
  ChannelFailuresBeforeRestart = 2
  SuccessCountToReset = 5
  MaxRestartsPerHour = 6
  PostRestartSleep = 30
  MaxLogBytes = 1048576
}

New-Item -ItemType Directory -Force -Path $ConfigDir, $StateDir | Out-Null
if (Test-Path -LiteralPath $ConfigPath) {
  $UserConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
  foreach ($prop in $UserConfig.PSObject.Properties) {
    $DefaultConfig[$prop.Name] = $prop.Value
  }
}
$Config = [pscustomobject]$DefaultConfig
$LogFile = Join-Path $StateDir "watchdog.log"

$createdNew = $false
$mutex = [System.Threading.Mutex]::new($false, "Global\OpenClawGatewayResilienceGuard", [ref]$createdNew)
if (-not $createdNew) {
  Write-Error "Another watchdog instance is already running."
  exit 0
}

function Write-Log {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
  $line | Tee-Object -FilePath $LogFile -Append
}

function Rotate-LogIfNeeded {
  if (Test-Path -LiteralPath $LogFile) {
    $size = (Get-Item -LiteralPath $LogFile).Length
    if ($size -gt [int64]$Config.MaxLogBytes) {
      Move-Item -LiteralPath $LogFile -Destination "$LogFile.1" -Force
      Write-Log "LOG: rotated because it exceeded $($Config.MaxLogBytes) bytes"
    }
  }
}

function Test-NativeEnabled {
  return -not (@("0", "false", "off", "no") -contains ([string]$Config.OpenClawNativeProbes).ToLowerInvariant())
}

function Save-ProbeOutput {
  param([string]$Name, [object[]]$Output)
  $path = Join-Path $StateDir $Name
  ($Output -join [Environment]::NewLine) | Out-File -LiteralPath $path -Encoding utf8
  return $path
}

function Invoke-OpenClawProbe {
  param([string[]]$Args, [string]$OutputName)
  if (-not (Test-NativeEnabled)) { return @{ Supported = $false; ExitCode = 127; Text = "" } }
  if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
    return @{ Supported = $false; ExitCode = 127; Text = "" }
  }
  $output = & openclaw @Args 2>&1
  $exitCode = $LASTEXITCODE
  $path = Save-ProbeOutput -Name $OutputName -Output $output
  $text = $output -join "`n"
  $unsupported = $text -match "unknown command|unknown option|unknown argument|unrecognized option|not recognized|invalid command"
  return @{ Supported = (-not $unsupported); ExitCode = $exitCode; Text = $text; Path = $path }
}

function Test-Http {
  param([string]$Url)
  if (-not $Url) { return $false }
  try {
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec ([int]$Config.MaxTime)
    return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
  } catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status) {
      return ($status -ge 200 -and $status -lt 500)
    }
    return $false
  }
}

function Test-Tcp {
  try {
    $client = [System.Net.Sockets.TcpClient]::new()
    $task = $client.ConnectAsync([string]$Config.GatewayHost, [int]$Config.GatewayPort)
    $ok = $task.Wait([int]$Config.ConnectTimeout * 1000) -and $client.Connected
    $client.Dispose()
    return $ok
  } catch {
    return $false
  }
}

function Test-OpenClawGateway {
  $probe = Invoke-OpenClawProbe -Args @("gateway", "status", "--json", "--require-rpc", "--timeout", "$($Config.OpenClawHealthTimeoutMs)") -OutputName "last-openclaw-gateway-status.json"
  if (-not $probe.Supported) { return 2 }
  if ($probe.ExitCode -eq 0) {
    if ($probe.Text -match '"ok"\s*:\s*false') {
      Write-Log "OPENCLAW GATEWAY FAIL: gateway status reported ok=false"
      return 1
    }
    if ($probe.Text -match '"degraded"\s*:\s*true') {
      Write-Log "OPENCLAW GATEWAY WARN: gateway RPC probe is reachable but degraded"
      if ($Config.OpenClawGatewayStrict) { return 1 }
    }
    return 0
  }
  Write-Log "OPENCLAW GATEWAY WARN: gateway status --require-rpc failed; falling back to local probes"
  return 2
}

function Test-Gateway {
  $native = Test-OpenClawGateway
  if ($native -eq 0) { return 0 }
  if ($native -eq 1) { return 1 }
  if (Test-Http -Url $Config.GatewayHealthUrl) { return 0 }
  if (Test-Tcp) { return 0 }
  Write-Log "GATEWAY FAIL: no healthy gateway detected"
  return 1
}

function Test-OpenClawChannel {
  $health = Invoke-OpenClawProbe -Args @("health", "--json", "--verbose", "--timeout", "$($Config.OpenClawHealthTimeoutMs)") -OutputName "last-openclaw-health.json"
  if ($health.Supported) {
    if ($health.ExitCode -eq 0 -and $health.Text -notmatch '"ok"\s*:\s*false') { return 0 }
    Write-Log "OPENCLAW CHANNEL FAIL: health live probe failed"
    return 1
  }
  $deep = Invoke-OpenClawProbe -Args @("status", "--deep") -OutputName "last-openclaw-status-deep.txt"
  if ($deep.Supported) {
    if ($deep.ExitCode -eq 0 -and $deep.Text -notmatch "logged[ -]?out|loggedOut|disconnected|unhealthy|healthy\s*:\s*false|probe\s*-?\s*failed|status\s*:\s*(409|410|411|412|413|414|415|500|501|502|503|504|515)|timeout") { return 0 }
    Write-Log "OPENCLAW CHANNEL FAIL: status --deep probe failed"
    return 1
  }
  if ($Config.OpenClawChannelsProbe) {
    $channels = Invoke-OpenClawProbe -Args @("channels", "status", "--probe") -OutputName "last-openclaw-channels-status.txt"
    if ($channels.Supported) {
      if ($channels.ExitCode -eq 0 -and $channels.Text -notmatch "logged[ -]?out|loggedOut|disconnected|unhealthy|healthy\s*:\s*false|probe\s*-?\s*failed|status\s*:\s*(409|410|411|412|413|414|415|500|501|502|503|504|515)|timeout") { return 0 }
      Write-Log "OPENCLAW CHANNEL FAIL: channels status probe failed"
      return 1
    }
  }
  return 2
}

function Test-Channel {
  $native = Test-OpenClawChannel
  if ($native -eq 0) { return $true }
  if ($native -eq 1) { return $false }
  return Test-Http -Url $Config.ChannelUrl
}

function Test-Network {
  foreach ($url in $Config.NetworkUrls) {
    if (Test-Http -Url $url) { return $true }
  }
  Write-Log "NETWORK FAIL: all network probes failed"
  return $false
}

function Get-RestartCountFile {
  return Join-Path $StateDir ("restarts.{0}" -f (Get-Date -Format "yyyyMMddHH"))
}

function Test-CanRestart {
  $file = Get-RestartCountFile
  $count = 0
  if (Test-Path -LiteralPath $file) { $count = [int](Get-Content -LiteralPath $file -ErrorAction SilentlyContinue) }
  return ($count -lt [int]$Config.MaxRestartsPerHour)
}

function Register-Restart {
  $file = Get-RestartCountFile
  $count = 0
  if (Test-Path -LiteralPath $file) { $count = [int](Get-Content -LiteralPath $file -ErrorAction SilentlyContinue) }
  Set-Content -LiteralPath $file -Value ($count + 1)
}

function Restart-Gateway {
  if (-not (Test-CanRestart)) {
    Write-Log "CIRCUIT OPEN: restart limit reached ($($Config.MaxRestartsPerHour)/hour); skip restart"
    return
  }
  if ($Config.RestartCommand) {
    Write-Log "ACTION: $($Config.RestartCommand)"
    cmd.exe /c $Config.RestartCommand 2>&1 | Tee-Object -FilePath $LogFile -Append
    if ($LASTEXITCODE -eq 0) {
      Register-Restart
    } else {
      Write-Log "ACTION FAIL: restart command returned non-zero"
    }
    return
  }
  if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    Write-Log "ACTION: openclaw gateway restart"
    & openclaw gateway restart 2>&1 | Tee-Object -FilePath $LogFile -Append
    if ($LASTEXITCODE -eq 0) {
      Register-Restart
    } else {
      Write-Log "ACTION FAIL: openclaw gateway restart failed"
    }
    return
  }
  Write-Log "ACTION FAIL: set RestartCommand in $ConfigPath; no restart method found"
}

function Get-BackoffInterval {
  param([int]$Failures)
  $interval = [int]$Config.BaseInterval
  for ($i = 1; $i -lt $Failures; $i++) {
    $interval *= 2
    if ($interval -ge [int]$Config.MaxInterval) { break }
  }
  return [Math]::Min($interval, [int]$Config.MaxInterval)
}

function Get-SleepInterval {
  $hour = [int](Get-Date -Format "HH")
  if ($hour -ge 1 -and $hour -lt 8) { return [int]$Config.NightInterval }
  return [int]$Config.BaseInterval
}

try {
  $failCount = 0
  $successCount = 0
  Write-Log "START: OpenClaw Gateway Resilience Guard $Version"
  Write-Log "CONFIG: $ConfigPath"

  while ($true) {
    Rotate-LogIfNeeded
    $gateway = Test-Gateway
    if ($gateway -eq 1) {
      $failCount += 1
      $successCount = 0
      Write-Log "CRITICAL: gateway appears down; restarting immediately"
      Restart-Gateway
      Start-Sleep -Seconds ([int]$Config.PostRestartSleep)
      continue
    }

    if (Test-Channel) {
      if ($failCount -gt 0) {
        $successCount += 1
        if ($successCount -ge [int]$Config.SuccessCountToReset) {
          Write-Log "RECOVERED: $($Config.SuccessCountToReset) consecutive channel probes succeeded; failure count reset"
          $failCount = 0
          $successCount = 0
        } else {
          Write-Log "RECOVERING: channel probe succeeded ($successCount/$($Config.SuccessCountToReset))"
        }
      }
      Start-Sleep -Seconds (Get-SleepInterval)
      continue
    }

    $failCount += 1
    $successCount = 0
    Write-Log "CHANNEL FAIL: channel probe failed ($failCount/$($Config.ChannelFailuresBeforeRestart))"
    if (-not (Test-Network)) {
      Write-Log "SAFEGUARD: looks like global network trouble; wait without restarting gateway"
      Start-Sleep -Seconds ([int]$Config.BaseInterval)
      continue
    }
    if ($failCount -lt [int]$Config.ChannelFailuresBeforeRestart) {
      Start-Sleep -Seconds ([int]$Config.BaseInterval)
      continue
    }
    $waitFor = Get-BackoffInterval -Failures $failCount
    Write-Log "BACKOFF: network is reachable; will re-check channel in ${waitFor}s before restart"
    Start-Sleep -Seconds $waitFor
    if (Test-Channel) {
      Write-Log "RECOVERED: channel came back before restart"
      $failCount = 0
      continue
    }
    Restart-Gateway
    Start-Sleep -Seconds ([int]$Config.PostRestartSleep)
  }
} finally {
  $mutex.ReleaseMutex() | Out-Null
  $mutex.Dispose()
}
