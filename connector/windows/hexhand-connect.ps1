<#
  HEXhand connector — runs next to a folder on this machine and lets the HEXhand
  container on hex-guy work inside it, exactly as if HEXhand were installed here.

  Usage (from any folder):
      cd D:\some\folder
      powershell -ExecutionPolicy Bypass -File hexhand-connect.ps1

  The folder you start it in becomes the workspace. Nothing outside it is reachable.
#>

param(
    [int]$Port = 3210,
    [string]$Token = "",
    [string]$Folder = "",
    [string]$TokenFile = "C:\Users\Superuser\.hexhand\connector_token.txt"
)

$ErrorActionPreference = "Stop"

if (-not $Folder) { $Folder = (Get-Location).Path }
if (-not (Test-Path $Folder)) { throw "Folder not found: $Folder" }
Set-Location $Folder
$Workspace = (Resolve-Path $Folder).Path.TrimEnd('\')

if (-not $Token) {
    if (Test-Path $TokenFile) { $Token = (Get-Content $TokenFile -Raw).Trim() }
    else { throw "No connector token. Expected $TokenFile" }
}

$script:Jobs = @{}
$script:JobSeq = 0

# A chat that ran several commands used to leave every job - plus its Process object and
# temp files - in memory for the life of the connector, so the client kept a live poll
# target for each one. Finished jobs now clear after a short grace; the pool is capped.
$script:JobTtlSeconds = 120
$script:MaxJobs = 16
$script:MaxOutputChars = 65536

function Clear-Jobs {
    $now = Get-Date
    foreach ($id in @($script:Jobs.Keys)) {
        $job = $script:Jobs[$id]
        $finished = $job.FinishedAt
        if (-not $finished) {
            if ($job.Process -and $job.Process.HasExited) { $finished = $now; $job.FinishedAt = $now }
            else { continue }
        }
        if (($now - $finished).TotalSeconds -ge $script:JobTtlSeconds) {
            foreach ($f in @($job.Out, $job.Err, $job.Wrap)) {
                if ($f -and (Test-Path $f)) { try { Remove-Item $f -Force } catch {} }
            }
            $script:Jobs.Remove($id)
        }
    }
}

function Get-Trimmed([string]$Text) {
    if (-not $Text) { return "" }
    if ($Text.Length -le $script:MaxOutputChars) { return $Text }
    $tail = $Text.Substring($Text.Length - $script:MaxOutputChars)
    return ("...(output truncated, showing the last " + $script:MaxOutputChars + " chars)" + [Environment]::NewLine + $tail)
}

function In-Workspace([string]$Path) {
    if (-not $Path) { return $Workspace }
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) }
            else { [System.IO.Path]::GetFullPath((Join-Path $Workspace $Path)) }
    $full = $full.TrimEnd('\')
    if ($full -ne $Workspace -and -not $full.StartsWith($Workspace + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the workspace: $Path"
    }
    return $full
}

function Text-Result([string]$Text, [bool]$IsError = $false) {
    return @{ content = @(@{ type = "text"; text = $Text }); isError = $IsError }
}

function Invoke-RunCommand($ToolInput) {
    $cmd = [string]$ToolInput.command
    $cwd = if ($ToolInput.cwd) { In-Workspace ([string]$ToolInput.cwd) } else { $Workspace }
    $timeout = if ($ToolInput.timeout) { [int]$ToolInput.timeout } else { 60000 }
    if ($timeout -gt 180000) { $timeout = 180000 }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c $cmd"
    $psi.WorkingDirectory = $cwd
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($timeout)) {
        try { $p.Kill($true) } catch {}
        return Text-Result ("TIMEOUT after " + $timeout + "ms`n" + $outTask.Result + $errTask.Result) $true
    }
    $out = $outTask.Result
    $err = $errTask.Result
    $text = $out
    if ($err) { $text = $text + "`nSTDERR:`n" + $err }
    $text = $text + "`nexit=" + $p.ExitCode
    return Text-Result $text ($p.ExitCode -ne 0)
}

function Invoke-StartCommand($ToolInput) {
    $cmd = [string]$ToolInput.command
    $cwd = if ($ToolInput.cwd) { In-Workspace ([string]$ToolInput.cwd) } else { $Workspace }
    Clear-Jobs
    if ($script:Jobs.Count -ge $script:MaxJobs) {
        return Text-Result ("too many commands are still tracked (" + [string]$script:Jobs.Count + ") - finished jobs clear automatically after " + [string]$script:JobTtlSeconds + " seconds, so poll or cancel an older job first") $false
    }
    $script:JobSeq++
    $id = "job-" + $script:JobSeq
    $outFile = Join-Path $env:TEMP ("catdesk-" + $id + ".out")
    $errFile = Join-Path $env:TEMP ("catdesk-" + $id + ".err")
    # Start-Process with redirected streams never exposes ExitCode, so the child reports
    # its own code on a marker line that poll strips out. Without this every finished
    # command looked like a failure and the client showed "Something went wrong".
    $wrapFile = Join-Path $env:TEMP ("catdesk-" + $id + ".cmd")
    $wrap = "@echo off`r`n" + $cmd + "`r`necho __HEXHAND_EXIT__=%ERRORLEVEL%"
    [System.IO.File]::WriteAllText($wrapFile, $wrap)
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList ("/c " + [char]34 + $wrapFile + [char]34) -WorkingDirectory $cwd `
         -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru -WindowStyle Hidden
    $script:Jobs[$id] = @{ Process = $p; Out = $outFile; Err = $errFile; Wrap = $wrapFile; Start = (Get-Date); FinishedAt = $null }
    return Text-Result ("started " + $id + " pid=" + $p.Id)
}

function Invoke-PollCommand($ToolInput) {
    Clear-Jobs
    $id = [string]$ToolInput.job_id
    $job = $script:Jobs[$id]
    if (-not $job) { return Text-Result ("job " + $id + " has finished and was cleared - do not poll it again") $false }
    $running = -not $job.Process.HasExited
    if (-not $running -and -not $job.FinishedAt) { $job.FinishedAt = Get-Date }
    # Start-Process -PassThru does not expose ExitCode until the object is refreshed, so the
    # old code compared $null against 0 and reported EVERY finished command as a failure.
    # That is what the client showed as "Something went wrong. Try again".
    $code = $null
    $rawOut = if (Test-Path $job.Out) { Get-Content $job.Out -Raw } else { "" }
    if (-not $running -and $rawOut) {
        $m = [regex]::Match($rawOut, "__HEXHAND_EXIT__=(-?\d+)")
        if ($m.Success) {
            $code = [int]$m.Groups[1].Value
            $rawOut = $rawOut.Substring(0, $m.Index).TrimEnd()
        }
    }
    $rawErr = if (Test-Path $job.Err) { Get-Content $job.Err -Raw } else { "" }
    $out = Get-Trimmed $rawOut
    $err = Get-Trimmed $rawErr
    if ($running) { $state = "running" }
    elseif ($null -ne $code) { $state = "done exit=" + $code }
    else { $state = "done" }
    $text = "[" + $state + "]`n" + $out
    if ($err) { $text = $text + "`nSTDERR:`n" + $err }
    if (-not $running) { $text = $text + "`n(this command has finished and the output above is complete - do not poll it again)" }
    return Text-Result $text ((-not $running) -and ($null -ne $code) -and ($code -ne 0))
}

function Invoke-CancelCommand($ToolInput) {
    $id = [string]$ToolInput.job_id
    $job = $script:Jobs[$id]
    if (-not $job) { return Text-Result ("unknown job " + $id) $true }
    if (-not $job.Process.HasExited) { try { $job.Process.Kill($true) } catch {} }
    $job.FinishedAt = Get-Date
    return Text-Result ("cancelled " + $id)
}

function Invoke-Read($ToolInput) {
    $parts = @()
    foreach ($p in $ToolInput.paths) {
        $full = In-Workspace ([string]$p)
        if (-not (Test-Path $full)) { $parts += ("--- " + $p + " ---`n(not found)"); continue }
        $text = Get-Content $full -Raw -ErrorAction SilentlyContinue
        if ($null -eq $text) { $text = "" }
        $parts += ("--- " + $p + " ---`n" + $text)
    }
    return Text-Result ($parts -join "`n`n")
}

function Invoke-Write($ToolInput) {
    $full = In-Workspace ([string]$ToolInput.path)
    $dir = Split-Path $full -Parent
    if (-not (Test-Path $dir)) {
        if ($ToolInput.create_dirs) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        else { return Text-Result ("parent directory missing: " + $dir) $true }
    }
    [System.IO.File]::WriteAllText($full, [string]$ToolInput.content)
    return Text-Result ("wrote " + $full + " (" + ([string]$ToolInput.content).Length + " chars)")
}

function Invoke-Edit($ToolInput) {
    $full = In-Workspace ([string]$ToolInput.path)
    if (-not (Test-Path $full)) { return Text-Result ("not found: " + $ToolInput.path) $true }
    $text = Get-Content $full -Raw
    $applied = 0
    foreach ($e in $ToolInput.edits) {
        if ($e.type -ne "replace") { return Text-Result ("unsupported edit type: " + $e.type) $true }
        $old = [string]$e.old_string
        $new = [string]$e.new_string
        if (-not $text.Contains($old)) { return Text-Result ("old_string not found in " + $ToolInput.path) $true }
        if ($e.replace_all) { $text = $text.Replace($old, $new) }
        else {
            $i = $text.IndexOf($old)
            $text = $text.Substring(0, $i) + $new + $text.Substring($i + $old.Length)
        }
        $applied++
    }
    [System.IO.File]::WriteAllText($full, $text)
    return Text-Result ("applied " + $applied + " edit(s) to " + $full)
}

function Invoke-Search($ToolInput) {
    $pattern = [string]$ToolInput.pattern
    $root = if ($ToolInput.path) { In-Workspace ([string]$ToolInput.path) } else { $Workspace }
    $glob = $ToolInput.glob
    $max = if ($ToolInput.max_matches) { [int]$ToolInput.max_matches } else { 200 }
    if ($max -gt 500) { $max = 500 }
    $skip = @('\node_modules\', '\.git\', '\target\', '\.venv\', '\AppData\', '\$Recycle.Bin\', '\OneDrive\')
    $matches = New-Object System.Collections.ArrayList
    $deadline = (Get-Date).AddSeconds(20)
    $truncated = $false
    $walker = $null
    try {
        $walker = [System.IO.Directory]::EnumerateFiles($root, '*', [System.IO.SearchOption]::AllDirectories).GetEnumerator()
    } catch { $walker = $null }
    if ($walker) {
        while ($true) {
            try { if (-not $walker.MoveNext()) { break } } catch { break }
            if ($matches.Count -ge $max -or (Get-Date) -gt $deadline) { $truncated = $true; break }
            $full = [string]$walker.Current
            $skipping = $false
            foreach ($s in $skip) { if ($full.IndexOf($s, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $skipping = $true; break } }
            if ($skipping) { continue }
            if ($glob -and ([System.IO.Path]::GetFileName($full) -notlike $glob)) { continue }
            try { if ((New-Object System.IO.FileInfo $full).Length -gt 2MB) { continue } } catch { continue }
            $lineNo = 0
            try {
                foreach ($line in [System.IO.File]::ReadLines($full)) {
                    $lineNo++
                    if ($line -like ("*" + $pattern + "*")) {
                        [void]$matches.Add(($full + ":" + $lineNo + ": " + $line.Trim()))
                        if ($matches.Count -ge $max) { $truncated = $true; break }
                    }
                }
            } catch { }
        }
    }
    $text = if ($matches.Count -eq 0) { "no matches for " + $pattern } else { ($matches -join "`n") }
    if ($truncated) { $text = $text + "`n(search stopped early - narrow it with path, glob or max_matches)" }
    return Text-Result $text $false
}

function Invoke-Delete($ToolInput) {
    $full = In-Workspace ([string]$ToolInput.path)
    if (-not (Test-Path $full)) { return Text-Result ("not found: " + $ToolInput.path) $true }
    if ((Get-Item $full).PSIsContainer -and -not $ToolInput.recursive) {
        return Text-Result "refusing to delete a directory without recursive=true" $true
    }
    Remove-Item $full -Recurse:([bool]$ToolInput.recursive) -Force
    return Text-Result ("deleted " + $full)
}

function Invoke-Tool([string]$Name, $ToolInput) {
    switch ($Name) {
        "run_command"         { return Invoke-RunCommand $ToolInput }
        "start_command"       { return Invoke-StartCommand $ToolInput }
        "poll_command"        { return Invoke-PollCommand $ToolInput }
        "cancel_command"      { return Invoke-CancelCommand $ToolInput }
        "read"                { return Invoke-Read $ToolInput }
        "write"               { return Invoke-Write $ToolInput }
        "edit"                { return Invoke-Edit $ToolInput }
        "search"              { return Invoke-Search $ToolInput }
        "delete"              { return Invoke-Delete $ToolInput }
        "hexhand_instruction" {
            return Text-Result ("You are working in " + $Workspace + " through the HEXhand connector. " +
                "Paths are relative to that folder and nothing outside it is reachable.")
        }
        "catdesk_instruction" { return Invoke-Tool "hexhand_instruction" $ToolInput }
        default { return Text-Result ("unknown tool: " + $Name) $true }
    }
}

$tools = @(
    @{ name = "run_command";    description = "Run a shell command in the workspace"; inputSchema = @{ type = "object"; properties = @{ command = @{ type = "string" }; cwd = @{ type = "string" }; timeout = @{ type = "integer" } }; required = @("command") } },
    @{ name = "start_command";  description = "Start a long-running command"; inputSchema = @{ type = "object"; properties = @{ command = @{ type = "string" }; cwd = @{ type = "string" } }; required = @("command") } },
    @{ name = "poll_command";   description = "Poll a started command"; inputSchema = @{ type = "object"; properties = @{ job_id = @{ type = "string" }; wait_ms = @{ type = "integer" } }; required = @("job_id") } },
    @{ name = "cancel_command"; description = "Cancel a started command"; inputSchema = @{ type = "object"; properties = @{ job_id = @{ type = "string" } }; required = @("job_id") } },
    @{ name = "read";           description = "Read files in the workspace"; inputSchema = @{ type = "object"; properties = @{ paths = @{ type = "array"; items = @{ type = "string" } } }; required = @("paths") } },
    @{ name = "write";          description = "Write a file"; inputSchema = @{ type = "object"; properties = @{ path = @{ type = "string" }; content = @{ type = "string" }; create_dirs = @{ type = "boolean" } }; required = @("path","content") } },
    @{ name = "edit";           description = "Replace text in a file"; inputSchema = @{ type = "object"; properties = @{ path = @{ type = "string" }; edits = @{ type = "array" } }; required = @("path","edits") } },
    @{ name = "search";         description = "Search text in the workspace"; inputSchema = @{ type = "object"; properties = @{ pattern = @{ type = "string" }; path = @{ type = "string" }; glob = @{ type = "string" }; max_matches = @{ type = "integer" } }; required = @("pattern") } },
    @{ name = "delete";         description = "Delete a file or folder"; inputSchema = @{ type = "object"; properties = @{ path = @{ type = "string" }; recursive = @{ type = "boolean" } }; required = @("path") } },
    @{ name = "hexhand_instruction"; description = "Workspace instructions"; inputSchema = @{ type = "object"; properties = @{} } }
)

$prefix = "http://+:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try {
    $listener.Start()
} catch {
    Write-Host ""
    Write-Host ("  Could not listen on port " + $Port + ": " + $_.Exception.Message) -ForegroundColor Red
    Write-Host "  Another connector may be running. Use the HEXhand here menu again." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  HEXhand connector" -ForegroundColor Cyan
Write-Host "  workspace : $Workspace"
Write-Host "  listening : $prefix"
Write-Host "  ready     : this folder is now the agent's workspace"
Write-Host "  stop      : Ctrl+C"
Write-Host ""

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    try {
        $auth = $req.Headers["Authorization"]
        if ($auth -ne "Bearer $Token") {
            $res.StatusCode = 401
            $body = '{"error":"unauthorized"}'
        } else {
            $reader = New-Object System.IO.StreamReader($req.InputStream)
            $raw = $reader.ReadToEnd()
            $payload = $raw | ConvertFrom-Json
            $dbg = "C:\Users\Superuser\.hexhand\connector\catdesk-debug.log"
            if ((Test-Path $dbg) -and ((Get-Item $dbg).Length -gt 5MB)) { try { Remove-Item $dbg -Force } catch {} }
            Add-Content -Path $dbg -Value ("METHOD=" + $payload.method + " NAME=" + $payload.params.name + " ARGKEYS=" + (($payload.params.arguments | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -join ",") + " RAW=" + $raw.Substring(0, [Math]::Min(200, $raw.Length)))
            $resp = @{ jsonrpc = "2.0"; id = $payload.id }
            switch ($payload.method) {
                "tools/list" {
                    $resp.result = @{ tools = $tools }
                }
                "tools/call" {
                    $name = $payload.params.name
                    $toolArgs = $payload.params.arguments
                    try {
                        $out = Invoke-Tool $name $toolArgs
                        $resp.result = $out
                    } catch {
                        $resp.result = @{ content = @(@{ type = "text"; text = ("ERROR: " + $_.Exception.Message) }); isError = $true }
                    }
                }
                default {
                    $resp.error = @{ code = -32601; message = ("Method not found: " + $payload.method) }
                }
            }
            $res.StatusCode = 200
            $body = ($resp | ConvertTo-Json -Depth 12 -Compress)
        }
    } catch {
        $res.StatusCode = 500
        $body = (@{ error = $_.Exception.Message } | ConvertTo-Json -Compress)
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $res.ContentType = "application/json"
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}
