param(
    [ValidateRange(1025, 65535)]
    [int]$Port = 18081
)

$ErrorActionPreference = 'Stop'

$labRoot = Split-Path -Parent $PSScriptRoot
$serverScriptPath = (Resolve-Path (Join-Path $labRoot 'src\api-server.ps1')).Path
$baseUrl = "http://127.0.0.1:$Port/api/v1"
$stdoutLogPath = Join-Path $env:TEMP "lab-work-4-api-$Port-out.log"
$stderrLogPath = Join-Path $env:TEMP "lab-work-4-api-$Port-err.log"

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected: $Expected. Actual: $Actual."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-ApiRequest {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        $Body
    )

    $bodyFilePath = $null

    try {
        $curlArgs = @(
            '--silent',
            '--show-error',
            '--max-time', '3',
            '--write-out', "`nHTTPSTATUS:%{http_code}",
            '-X', $Method
        )

        if ($null -ne $Body) {
            $jsonBody = $Body | ConvertTo-Json -Depth 10
            $bodyFilePath = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllText($bodyFilePath, $jsonBody, [System.Text.UTF8Encoding]::new($false))
            $curlArgs += @(
                '-H', 'Content-Type: application/json',
                '--data-binary', "@$bodyFilePath"
            )
        }

        $curlArgs += "$baseUrl$Path"
        $rawResult = (& curl.exe @curlArgs 2>&1) -join "`n"

        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed for $Method ${Path}: $rawResult"
        }

        $statusMarkerIndex = $rawResult.LastIndexOf('HTTPSTATUS:')
        if ($statusMarkerIndex -lt 0) {
            throw "Unable to parse HTTP status for $Method ${Path}. Response: $rawResult"
        }

        $rawBody = $rawResult.Substring(0, $statusMarkerIndex).TrimEnd("`r", "`n")
        $statusCode = [int]$rawResult.Substring($statusMarkerIndex + 'HTTPSTATUS:'.Length).Trim()
        $jsonBody = $null

        if (-not [string]::IsNullOrWhiteSpace($rawBody)) {
            try {
                $jsonBody = $rawBody | ConvertFrom-Json
            }
            catch {
                $jsonBody = $null
            }
        }

        return [pscustomobject]@{
            StatusCode = $statusCode
            RawBody = $rawBody
            Json = $jsonBody
        }
    }
    finally {
        if ($null -ne $bodyFilePath -and (Test-Path $bodyFilePath)) {
            Remove-Item $bodyFilePath -Force
        }
    }
}

function Wait-ApiReady {
    param([Parameter(Mandatory)]$Process)

    for ($attempt = 1; $attempt -le 40; $attempt++) {
        if ($Process.HasExited) {
            throw "API server exited unexpectedly with code $($Process.ExitCode)."
        }

        try {
            $response = Invoke-ApiRequest -Method 'GET' -Path '/health'
            if ($response.StatusCode -eq 200 -and $response.Json.status -eq 'UP') {
                return
            }
        }
        catch {
        }

        Start-Sleep -Milliseconds 250
    }

    throw "API did not start on $baseUrl within the expected time."
}

$escapedServerScriptPath = $serverScriptPath -replace "'", "''"
$serverCommand = "& '$escapedServerScriptPath' -Port $Port"
Remove-Item $stdoutLogPath, $stderrLogPath -Force -ErrorAction SilentlyContinue

$serverProcess = Start-Process powershell -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-Command', $serverCommand
) -PassThru -RedirectStandardOutput $stdoutLogPath -RedirectStandardError $stderrLogPath

try {
    Wait-ApiReady -Process $serverProcess
    Write-Host "API is ready at $baseUrl"

    Write-Host 'Test 1: POST /devices success'
    $createDeviceResponse = Invoke-ApiRequest -Method 'POST' -Path '/devices' -Body @{
        clientId = 1
        deviceTypeId = 1
        brand = 'Samsung'
        model = 'Galaxy S21'
    }
    Assert-Equal -Expected 201 -Actual $createDeviceResponse.StatusCode -Message 'POST /devices should create a device.'
    Assert-Equal -Expected 'CREATED' -Actual $createDeviceResponse.Json.status -Message 'New device should have CREATED status.'
    $createdDeviceId = [int]$createDeviceResponse.Json.id

    Write-Host 'Test 2: POST /devices validation error'
    $createDeviceInvalidResponse = Invoke-ApiRequest -Method 'POST' -Path '/devices' -Body @{
        clientId = 1
        deviceTypeId = 1
        model = 'Galaxy S21'
    }
    Assert-Equal -Expected 400 -Actual $createDeviceInvalidResponse.StatusCode -Message 'POST /devices should reject incomplete payload.'
    Assert-True -Condition ($createDeviceInvalidResponse.Json.error.message -like "*brand*") -Message 'Validation error for POST /devices should mention brand.'

    Write-Host 'Test 3: GET /devices/{id} success'
    $getDeviceResponse = Invoke-ApiRequest -Method 'GET' -Path "/devices/$createdDeviceId"
    Assert-Equal -Expected 200 -Actual $getDeviceResponse.StatusCode -Message 'GET /devices/{id} should return an existing device.'
    Assert-Equal -Expected $createdDeviceId -Actual ([int]$getDeviceResponse.Json.id) -Message 'GET /devices/{id} should return the created device.'

    Write-Host 'Test 4: GET /devices/{id} not found'
    $getMissingDeviceResponse = Invoke-ApiRequest -Method 'GET' -Path '/devices/999'
    Assert-Equal -Expected 404 -Actual $getMissingDeviceResponse.StatusCode -Message 'GET /devices/{id} should return 404 for unknown device.'

    Write-Host 'Test 5: POST /inspection success'
    $inspectionResponse = Invoke-ApiRequest -Method 'POST' -Path '/inspection' -Body @{
        deviceId = $createdDeviceId
        condition = 'GOOD'
        screenState = 'OK'
        batteryHealth = 91
        comment = 'Automated inspection'
    }
    Assert-Equal -Expected 201 -Actual $inspectionResponse.StatusCode -Message 'POST /inspection should create inspection and offer.'
    Assert-Equal -Expected $createdDeviceId -Actual ([int]$inspectionResponse.Json.inspection.deviceId) -Message 'Inspection should reference the created device.'
    $createdOfferId = [int]$inspectionResponse.Json.offer.id

    Write-Host 'Test 6: POST /inspection duplicate'
    $inspectionDuplicateResponse = Invoke-ApiRequest -Method 'POST' -Path '/inspection' -Body @{
        deviceId = $createdDeviceId
        condition = 'GOOD'
        screenState = 'OK'
        batteryHealth = 91
    }
    Assert-Equal -Expected 409 -Actual $inspectionDuplicateResponse.StatusCode -Message 'POST /inspection should reject duplicate inspection.'

    Write-Host 'Test 7: GET /offers/{deviceId} success'
    $getOfferResponse = Invoke-ApiRequest -Method 'GET' -Path "/offers/$createdDeviceId"
    Assert-Equal -Expected 200 -Actual $getOfferResponse.StatusCode -Message 'GET /offers/{deviceId} should return the offer.'
    Assert-Equal -Expected $createdOfferId -Actual ([int]$getOfferResponse.Json.id) -Message 'GET /offers/{deviceId} should return the created offer.'

    Write-Host 'Test 8: GET /offers/{deviceId} not found'
    $getMissingOfferResponse = Invoke-ApiRequest -Method 'GET' -Path '/offers/999'
    Assert-Equal -Expected 404 -Actual $getMissingOfferResponse.StatusCode -Message 'GET /offers/{deviceId} should return 404 for unknown device.'

    Write-Host 'Test 9: POST /offers/{id}/confirm success'
    $confirmOfferResponse = Invoke-ApiRequest -Method 'POST' -Path "/offers/$createdOfferId/confirm"
    Assert-Equal -Expected 200 -Actual $confirmOfferResponse.StatusCode -Message 'POST /offers/{id}/confirm should confirm the offer.'
    Assert-Equal -Expected 'CONFIRMED' -Actual $confirmOfferResponse.Json.status -Message 'Confirmed offer should have CONFIRMED status.'

    Write-Host 'Test 10: POST /offers/{id}/confirm duplicate'
    $confirmOfferDuplicateResponse = Invoke-ApiRequest -Method 'POST' -Path "/offers/$createdOfferId/confirm"
    Assert-Equal -Expected 409 -Actual $confirmOfferDuplicateResponse.StatusCode -Message 'POST /offers/{id}/confirm should reject repeated confirmation.'

    Write-Host 'Test 11: POST /payments success'
    $paymentResponse = Invoke-ApiRequest -Method 'POST' -Path '/payments' -Body @{
        offerId = $createdOfferId
        paymentMethod = 'CARD'
    }
    Assert-Equal -Expected 201 -Actual $paymentResponse.StatusCode -Message 'POST /payments should create a payment for a confirmed offer.'
    Assert-Equal -Expected 'PAID' -Actual $paymentResponse.Json.status -Message 'Created payment should have PAID status.'

    Write-Host 'Test 12: POST /payments invalid state'
    $paymentInvalidStateResponse = Invoke-ApiRequest -Method 'POST' -Path '/payments' -Body @{
        offerId = 1
        paymentMethod = 'CARD'
    }
    Assert-Equal -Expected 409 -Actual $paymentInvalidStateResponse.StatusCode -Message 'POST /payments should reject payment for unconfirmed offer.'

    Write-Host 'Test 13: POST /transfers success'
    $transferResponse = Invoke-ApiRequest -Method 'POST' -Path '/transfers' -Body @{
        deviceId = $createdDeviceId
        partnerName = 'Recycle Hub'
    }
    Assert-Equal -Expected 201 -Actual $transferResponse.StatusCode -Message 'POST /transfers should transfer a paid device.'
    Assert-Equal -Expected 'TRANSFERRED' -Actual $transferResponse.Json.status -Message 'Transferred device should have TRANSFERRED status.'

    Write-Host 'Test 14: POST /transfers invalid state'
    $transferInvalidStateResponse = Invoke-ApiRequest -Method 'POST' -Path '/transfers' -Body @{
        deviceId = 1
        partnerName = 'Recycle Hub'
    }
    Assert-Equal -Expected 409 -Actual $transferInvalidStateResponse.StatusCode -Message 'POST /transfers should reject unpaid device.'

    Write-Host 'Test 15: PUT /device-types/{id} success'
    $putDeviceTypeResponse = Invoke-ApiRequest -Method 'PUT' -Path '/device-types/3' -Body @{
        name = 'Premium Tablet'
    }
    Assert-Equal -Expected 200 -Actual $putDeviceTypeResponse.StatusCode -Message 'PUT /device-types/{id} should update device type.'
    Assert-Equal -Expected 'Premium Tablet' -Actual $putDeviceTypeResponse.Json.name -Message 'PUT /device-types/{id} should update the name.'

    Write-Host 'Test 16: PUT /device-types/{id} not found'
    $putMissingDeviceTypeResponse = Invoke-ApiRequest -Method 'PUT' -Path '/device-types/999' -Body @{
        name = 'Unknown Type'
    }
    Assert-Equal -Expected 404 -Actual $putMissingDeviceTypeResponse.StatusCode -Message 'PUT /device-types/{id} should return 404 for unknown device type.'

    Write-Host 'Test 17: DELETE /device-types/{id} success'
    $deleteDeviceTypeResponse = Invoke-ApiRequest -Method 'DELETE' -Path '/device-types/3'
    Assert-Equal -Expected 200 -Actual $deleteDeviceTypeResponse.StatusCode -Message 'DELETE /device-types/{id} should delete an unused device type.'
    Assert-Equal -Expected 'DELETED' -Actual $deleteDeviceTypeResponse.Json.status -Message 'DELETE /device-types/{id} should return DELETED status.'

    Write-Host 'Test 18: DELETE /device-types/{id} linked conflict'
    $deleteLinkedDeviceTypeResponse = Invoke-ApiRequest -Method 'DELETE' -Path '/device-types/1'
    Assert-Equal -Expected 409 -Actual $deleteLinkedDeviceTypeResponse.StatusCode -Message 'DELETE /device-types/{id} should reject linked device type.'

    Write-Host 'All API tests passed.'
}
catch {
    if ($serverProcess.HasExited) {
        Write-Host "API server exited with code $($serverProcess.ExitCode)."
    }

    $stdoutLog = Get-Content $stdoutLogPath -ErrorAction SilentlyContinue | Out-String
    $stderrLog = Get-Content $stderrLogPath -ErrorAction SilentlyContinue | Out-String

    if (-not [string]::IsNullOrWhiteSpace($stdoutLog)) {
        Write-Host 'Server stdout:'
        Write-Host $stdoutLog
    }

    if (-not [string]::IsNullOrWhiteSpace($stderrLog)) {
        Write-Host 'Server stderr:'
        Write-Host $stderrLog
    }

    throw
}
finally {
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
    }

    Remove-Item $stdoutLogPath, $stderrLogPath -Force -ErrorAction SilentlyContinue
}
