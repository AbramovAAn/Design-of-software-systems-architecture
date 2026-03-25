param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8090
)

$ErrorActionPreference = 'Stop'

$BaseUrl = "http://localhost:$Port/"

$script:state = @{
    nextDeviceId = 3
    nextInspectionId = 2
    nextOfferId = 2
    nextPaymentId = 1
    nextTransferId = 1
    clients = @(
        @{ id = 1; fullName = 'Ivan Petrov'; phone = '+79990000001' }
        @{ id = 2; fullName = 'Anna Sidorova'; phone = '+79990000002' }
    )
    deviceTypes = @(
        @{ id = 1; name = 'Smartphone' }
        @{ id = 2; name = 'Laptop' }
        @{ id = 3; name = 'Tablet' }
    )
    devices = @(
        @{
            id = 1
            clientId = 1
            deviceTypeId = 1
            brand = 'Apple'
            model = 'iPhone 12'
            status = 'CREATED'
            createdAt = '2026-03-19T10:00:00Z'
        }
        @{
            id = 2
            clientId = 2
            deviceTypeId = 2
            brand = 'Lenovo'
            model = 'IdeaPad 5'
            status = 'INSPECTED'
            createdAt = '2026-03-19T10:10:00Z'
        }
    )
    inspections = @(
        @{
            id = 1
            deviceId = 2
            condition = 'GOOD'
            screenState = 'OK'
            batteryHealth = 86
            comment = 'Minor scratches on the lid'
            createdAt = '2026-03-19T10:20:00Z'
        }
    )
    offers = @(
        @{
            id = 1
            deviceId = 2
            amount = 38000
            currency = 'RUB'
            status = 'CREATED'
            createdAt = '2026-03-19T10:25:00Z'
        }
    )
    payments = @()
    transfers = @()
}

function ConvertTo-PlainObject {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) {
            $result[$key] = ConvertTo-PlainObject -Value $Value[$key]
        }
        return $result
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(ConvertTo-PlainObject -Value $item)
        }
        return $items
    }

    return $Value
}

function Send-JsonResponse {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)]$Body
    )

    $json = (ConvertTo-PlainObject -Value $Body) | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    Send-RawHttpResponse -Context $Context -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -BodyBytes $buffer
}

function Send-EmptyResponse {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][int]$StatusCode
    )

    Send-RawHttpResponse -Context $Context -StatusCode $StatusCode -ContentType 'text/plain; charset=utf-8' -BodyBytes ([byte[]]::new(0))
}

function Read-JsonBody {
    param([Parameter(Mandatory)]$Request)

    $raw = $Request.BodyRaw

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Get-StatusDescription {
    param([int]$StatusCode)

    switch ($StatusCode) {
        200 { 'OK' }
        201 { 'Created' }
        204 { 'No Content' }
        400 { 'Bad Request' }
        404 { 'Not Found' }
        409 { 'Conflict' }
        500 { 'Internal Server Error' }
        default { 'OK' }
    }
}

function Send-RawHttpResponse {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][int]$StatusCode,
        [Parameter(Mandatory)][string]$ContentType,
        [Parameter(Mandatory)][byte[]]$BodyBytes
    )

    $statusText = Get-StatusDescription -StatusCode $StatusCode
    $headerText = @(
        "HTTP/1.1 $StatusCode $statusText"
        "Content-Type: $ContentType"
        "Content-Length: $($BodyBytes.Length)"
        'Access-Control-Allow-Origin: *'
        'Access-Control-Allow-Headers: Content-Type'
        'Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS'
        'Connection: close'
        ''
        ''
    ) -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headerText)
    $stream = $Context.Stream
    $stream.Write($headerBytes, 0, $headerBytes.Length)

    if ($BodyBytes.Length -gt 0) {
        $stream.Write($BodyBytes, 0, $BodyBytes.Length)
    }

    $stream.Flush()
}

function Read-HttpRequest {
    param([Parameter(Mandatory)][System.Net.Sockets.TcpClient]$Client)

    $stream = $Client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false, 8192, $true)
    $requestLine = $reader.ReadLine()

    if ([string]::IsNullOrWhiteSpace($requestLine)) {
        return $null
    }

    $parts = $requestLine.Split(' ')
    if ($parts.Length -lt 2) {
        throw 'Malformed HTTP request line.'
    }

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($line -eq $null -or $line -eq '') {
            break
        }

        $separatorIndex = $line.IndexOf(':')
        if ($separatorIndex -gt 0) {
            $name = $line.Substring(0, $separatorIndex).Trim()
            $value = $line.Substring($separatorIndex + 1).Trim()
            $headers[$name] = $value
        }
    }

    $bodyRaw = ''
    $contentLength = 0
    if ($headers.ContainsKey('Content-Length')) {
        $contentLength = [int]$headers['Content-Length']
    }

    if ($contentLength -gt 0) {
        $buffer = New-Object char[] $contentLength
        $read = 0
        while ($read -lt $contentLength) {
            $chunk = $reader.Read($buffer, $read, $contentLength - $read)
            if ($chunk -le 0) {
                break
            }
            $read += $chunk
        }
        $bodyRaw = -join $buffer[0..($read - 1)]
    }

    $uri = [Uri]("http://localhost" + $parts[1])
    return @{
        Method = $parts[0].ToUpperInvariant()
        Path = $uri.AbsolutePath
        Headers = $headers
        BodyRaw = $bodyRaw
    }
}

function Get-PathSegments {
    param([string]$AbsolutePath)

    return @($AbsolutePath.Trim('/').Split('/', [System.StringSplitOptions]::RemoveEmptyEntries))
}

function Get-DeviceById {
    param([int]$Id)
    return $script:state.devices | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Get-OfferById {
    param([int]$Id)
    return $script:state.offers | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Get-OfferByDeviceId {
    param([int]$DeviceId)
    return $script:state.offers | Where-Object { $_.deviceId -eq $DeviceId } | Select-Object -First 1
}

function Get-DeviceTypeById {
    param([int]$Id)
    return $script:state.deviceTypes | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function New-ApiError {
    param([string]$Message)
    return @{
        error = @{
            message = $Message
        }
    }
}

function Test-BodyField {
    param(
        [Parameter(Mandatory)]$Body,
        [Parameter(Mandatory)][string]$Field
    )

    return $Body.PSObject.Properties.Name -contains $Field
}

function Handle-GetHealth {
    param($Context)

    Send-JsonResponse -Context $Context -StatusCode 200 -Body @{
        service = 'device-inspection-api'
        version = 'v1'
        status = 'UP'
    }
}

function Handle-GetDevices {
    param($Context)

    Send-JsonResponse -Context $Context -StatusCode 200 -Body @{
        items = $script:state.devices
        total = $script:state.devices.Count
    }
}

function Handle-GetDeviceById {
    param($Context, [int]$DeviceId)

    $device = Get-DeviceById -Id $DeviceId
    if ($null -eq $device) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Device not found.')
        return
    }

    Send-JsonResponse -Context $Context -StatusCode 200 -Body $device
}

function Handle-PostDevices {
    param($Context)

    $body = Read-JsonBody -Request $Context.Request
    if ($null -eq $body) {
        Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message 'Request body is required.')
        return
    }

    $required = @('clientId', 'deviceTypeId', 'brand', 'model')
    foreach ($field in $required) {
        if (-not (Test-BodyField -Body $body -Field $field) -or [string]::IsNullOrWhiteSpace([string]$body.$field)) {
            Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message "Field '$field' is required.")
            return
        }
    }

    $client = $script:state.clients | Where-Object { $_.id -eq [int]$body.clientId } | Select-Object -First 1
    if ($null -eq $client) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Client not found.')
        return
    }

    $deviceType = $script:state.deviceTypes | Where-Object { $_.id -eq [int]$body.deviceTypeId } | Select-Object -First 1
    if ($null -eq $deviceType) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Device type not found.')
        return
    }

    $device = @{
        id = $script:state.nextDeviceId
        clientId = [int]$body.clientId
        deviceTypeId = [int]$body.deviceTypeId
        brand = [string]$body.brand
        model = [string]$body.model
        status = 'CREATED'
        createdAt = [DateTime]::UtcNow.ToString('s') + 'Z'
    }

    $script:state.nextDeviceId++
    $script:state.devices += $device

    Send-JsonResponse -Context $Context -StatusCode 201 -Body $device
}

function Handle-PostInspection {
    param($Context)

    $body = Read-JsonBody -Request $Context.Request
    if ($null -eq $body) {
        Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message 'Request body is required.')
        return
    }

    $required = @('deviceId', 'condition', 'screenState', 'batteryHealth')
    foreach ($field in $required) {
        if (-not (Test-BodyField -Body $body -Field $field) -or [string]::IsNullOrWhiteSpace([string]$body.$field)) {
            Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message "Field '$field' is required.")
            return
        }
    }

    $device = Get-DeviceById -Id ([int]$body.deviceId)
    if ($null -eq $device) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Device not found.')
        return
    }

    if ((Get-OfferByDeviceId -DeviceId $device.id) -ne $null) {
        Send-JsonResponse -Context $Context -StatusCode 409 -Body (New-ApiError -Message 'Inspection already completed for this device.')
        return
    }

    $inspection = @{
        id = $script:state.nextInspectionId
        deviceId = $device.id
        condition = [string]$body.condition
        screenState = [string]$body.screenState
        batteryHealth = [int]$body.batteryHealth
        comment = [string]$body.comment
        createdAt = [DateTime]::UtcNow.ToString('s') + 'Z'
    }

    $offerAmount = switch ($inspection.condition) {
        'EXCELLENT' { 50000 }
        'GOOD' { 35000 }
        'FAIR' { 22000 }
        default { 12000 }
    }

    $offer = @{
        id = $script:state.nextOfferId
        deviceId = $device.id
        amount = $offerAmount
        currency = 'RUB'
        status = 'CREATED'
        createdAt = [DateTime]::UtcNow.ToString('s') + 'Z'
    }

    $device.status = 'INSPECTED'
    $script:state.nextInspectionId++
    $script:state.nextOfferId++
    $script:state.inspections += $inspection
    $script:state.offers += $offer

    Send-JsonResponse -Context $Context -StatusCode 201 -Body @{
        inspection = $inspection
        offer = $offer
    }
}

function Handle-GetOfferByDeviceId {
    param($Context, [int]$DeviceId)

    $device = Get-DeviceById -Id $DeviceId
    if ($null -eq $device) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Device not found.')
        return
    }

    $offer = Get-OfferByDeviceId -DeviceId $DeviceId
    if ($null -eq $offer) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Offer not found for this device.')
        return
    }

    Send-JsonResponse -Context $Context -StatusCode 200 -Body $offer
}

function Handle-PostOfferConfirm {
    param($Context, [int]$OfferId)

    $offer = Get-OfferById -Id $OfferId
    if ($null -eq $offer) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Offer not found.')
        return
    }

    if ($offer.status -eq 'CONFIRMED') {
        Send-JsonResponse -Context $Context -StatusCode 409 -Body (New-ApiError -Message 'Offer already confirmed.')
        return
    }

    $offer.status = 'CONFIRMED'
    $device = Get-DeviceById -Id $offer.deviceId
    if ($null -ne $device) {
        $device.status = 'OFFER_CONFIRMED'
    }

    Send-JsonResponse -Context $Context -StatusCode 200 -Body @{
        id = $offer.id
        status = $offer.status
        confirmedAt = [DateTime]::UtcNow.ToString('s') + 'Z'
    }
}

function Handle-PostPayments {
    param($Context)

    $body = Read-JsonBody -Request $Context.Request
    if ($null -eq $body) {
        Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message 'Request body is required.')
        return
    }

    $required = @('offerId', 'paymentMethod')
    foreach ($field in $required) {
        if (-not (Test-BodyField -Body $body -Field $field) -or [string]::IsNullOrWhiteSpace([string]$body.$field)) {
            Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message "Field '$field' is required.")
            return
        }
    }

    $offer = Get-OfferById -Id ([int]$body.offerId)
    if ($null -eq $offer) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Offer not found.')
        return
    }

    if ($offer.status -ne 'CONFIRMED') {
        Send-JsonResponse -Context $Context -StatusCode 409 -Body (New-ApiError -Message 'Payment is allowed only for confirmed offers.')
        return
    }

    $payment = @{
        id = $script:state.nextPaymentId
        offerId = $offer.id
        amount = $offer.amount
        paymentMethod = [string]$body.paymentMethod
        status = 'PAID'
        createdAt = [DateTime]::UtcNow.ToString('s') + 'Z'
    }

    $script:state.nextPaymentId++
    $script:state.payments += $payment

    $device = Get-DeviceById -Id $offer.deviceId
    if ($null -ne $device) {
        $device.status = 'PAID'
    }

    Send-JsonResponse -Context $Context -StatusCode 201 -Body $payment
}

function Handle-PostTransfers {
    param($Context)

    $body = Read-JsonBody -Request $Context.Request
    if ($null -eq $body) {
        Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message 'Request body is required.')
        return
    }

    $required = @('deviceId', 'partnerName')
    foreach ($field in $required) {
        if (-not (Test-BodyField -Body $body -Field $field) -or [string]::IsNullOrWhiteSpace([string]$body.$field)) {
            Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message "Field '$field' is required.")
            return
        }
    }

    $device = Get-DeviceById -Id ([int]$body.deviceId)
    if ($null -eq $device) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Device not found.')
        return
    }

    if ($device.status -ne 'PAID') {
        Send-JsonResponse -Context $Context -StatusCode 409 -Body (New-ApiError -Message 'Device can be transferred only after payment.')
        return
    }

    $transfer = @{
        id = $script:state.nextTransferId
        deviceId = $device.id
        partnerName = [string]$body.partnerName
        status = 'TRANSFERRED'
        createdAt = [DateTime]::UtcNow.ToString('s') + 'Z'
    }

    $script:state.nextTransferId++
    $script:state.transfers += $transfer
    $device.status = 'TRANSFERRED'

    Send-JsonResponse -Context $Context -StatusCode 201 -Body $transfer
}

function Handle-PutDeviceType {
    param($Context, [int]$DeviceTypeId)

    $deviceType = Get-DeviceTypeById -Id $DeviceTypeId
    if ($null -eq $deviceType) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Device type not found.')
        return
    }

    $body = Read-JsonBody -Request $Context.Request
    if ($null -eq $body) {
        Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message 'Request body is required.')
        return
    }

    if (-not (Test-BodyField -Body $body -Field 'name') -or [string]::IsNullOrWhiteSpace([string]$body.name)) {
        Send-JsonResponse -Context $Context -StatusCode 400 -Body (New-ApiError -Message "Field 'name' is required.")
        return
    }

    $normalizedName = ([string]$body.name).Trim()
    $duplicate = $script:state.deviceTypes |
        Where-Object { $_.id -ne $DeviceTypeId -and $_.name -eq $normalizedName } |
        Select-Object -First 1
    if ($null -ne $duplicate) {
        Send-JsonResponse -Context $Context -StatusCode 409 -Body (New-ApiError -Message 'Device type with this name already exists.')
        return
    }

    $deviceType.name = $normalizedName
    $deviceType.updatedAt = [DateTime]::UtcNow.ToString('s') + 'Z'

    Send-JsonResponse -Context $Context -StatusCode 200 -Body $deviceType
}

function Handle-DeleteDeviceType {
    param($Context, [int]$DeviceTypeId)

    $deviceType = Get-DeviceTypeById -Id $DeviceTypeId
    if ($null -eq $deviceType) {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Device type not found.')
        return
    }

    $linkedDevice = $script:state.devices | Where-Object { $_.deviceTypeId -eq $DeviceTypeId } | Select-Object -First 1
    if ($null -ne $linkedDevice) {
        Send-JsonResponse -Context $Context -StatusCode 409 -Body (New-ApiError -Message 'Device type cannot be deleted because it is linked to existing devices.')
        return
    }

    $script:state.deviceTypes = @($script:state.deviceTypes | Where-Object { $_.id -ne $DeviceTypeId })

    Send-JsonResponse -Context $Context -StatusCode 200 -Body @{
        id = $DeviceTypeId
        status = 'DELETED'
        deletedAt = [DateTime]::UtcNow.ToString('s') + 'Z'
    }
}

function Handle-Request {
    param($Context)

    $request = $Context.Request
    $method = $request.Method
    $path = $request.Path
    $segments = Get-PathSegments -AbsolutePath $path

    if ($method -eq 'OPTIONS') {
        Send-EmptyResponse -Context $Context -StatusCode 204
        return
    }

    if ($segments.Count -lt 2 -or $segments[0] -ne 'api' -or $segments[1] -ne 'v1') {
        Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Route not found.')
        return
    }

    $resource = @($segments | Select-Object -Skip 2)

    if ($method -eq 'GET' -and $resource.Count -eq 1 -and $resource[0] -eq 'health') {
        Handle-GetHealth -Context $Context
        return
    }

    if ($method -eq 'GET' -and $resource.Count -eq 1 -and $resource[0] -eq 'devices') {
        Handle-GetDevices -Context $Context
        return
    }

    if ($method -eq 'POST' -and $resource.Count -eq 1 -and $resource[0] -eq 'devices') {
        Handle-PostDevices -Context $Context
        return
    }

    if ($method -eq 'GET' -and $resource.Count -eq 2 -and $resource[0] -eq 'devices' -and $resource[1] -match '^\d+$') {
        Handle-GetDeviceById -Context $Context -DeviceId ([int]$resource[1])
        return
    }

    if ($method -eq 'POST' -and $resource.Count -eq 1 -and $resource[0] -eq 'inspection') {
        Handle-PostInspection -Context $Context
        return
    }

    if ($method -eq 'GET' -and $resource.Count -eq 2 -and $resource[0] -eq 'offers' -and $resource[1] -match '^\d+$') {
        Handle-GetOfferByDeviceId -Context $Context -DeviceId ([int]$resource[1])
        return
    }

    if ($method -eq 'POST' -and $resource.Count -eq 3 -and $resource[0] -eq 'offers' -and $resource[1] -match '^\d+$' -and $resource[2] -eq 'confirm') {
        Handle-PostOfferConfirm -Context $Context -OfferId ([int]$resource[1])
        return
    }

    if ($method -eq 'POST' -and $resource.Count -eq 1 -and $resource[0] -eq 'payments') {
        Handle-PostPayments -Context $Context
        return
    }

    if ($method -eq 'POST' -and $resource.Count -eq 1 -and $resource[0] -eq 'transfers') {
        Handle-PostTransfers -Context $Context
        return
    }

    if ($method -eq 'PUT' -and $resource.Count -eq 2 -and $resource[0] -eq 'device-types' -and $resource[1] -match '^\d+$') {
        Handle-PutDeviceType -Context $Context -DeviceTypeId ([int]$resource[1])
        return
    }

    if ($method -eq 'DELETE' -and $resource.Count -eq 2 -and $resource[0] -eq 'device-types' -and $resource[1] -match '^\d+$') {
        Handle-DeleteDeviceType -Context $Context -DeviceTypeId ([int]$resource[1])
        return
    }

    Send-JsonResponse -Context $Context -StatusCode 404 -Body (New-ApiError -Message 'Route not found.')
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()

Write-Host "REST API is running at $BaseUrl"
Write-Host "Press Ctrl+C to stop the server."

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $context = $null
        try {
            $request = Read-HttpRequest -Client $client
            if ($null -eq $request) {
                $client.Close()
                continue
            }

            $context = @{
                Request = $request
                Stream = $client.GetStream()
            }
            Handle-Request -Context $context
        }
        catch {
            if ($null -ne $context) {
                Send-JsonResponse -Context $context -StatusCode 500 -Body @{
                    error = @{
                        message = 'Internal server error.'
                        details = $_.Exception.Message
                    }
                }
            }
        }
        finally {
            if ($null -ne $client) {
                $client.Close()
            }
        }
    }
}
finally {
    $listener.Stop()
}
