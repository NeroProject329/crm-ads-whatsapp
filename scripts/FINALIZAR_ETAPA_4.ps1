param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,

    [int]$SmokePort = 3108
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$EmployeeId = $EmployeeId.Trim()

if ($EmployeeId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
    throw "EmployeeId invalido. Informe employee.id em formato UUID."
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "==== $Description ====" -ForegroundColor Cyan

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Description falhou com exit code $LASTEXITCODE."
    }

    Write-Host "[OK] $Description" -ForegroundColor Green
}

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$Value
    )

    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
    }
}

function Invoke-Json {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [string]$AccessToken,

        [AllowNull()]
        [hashtable]$Body
    )

    $Parameters = @{
        Uri        = $Uri
        Method     = $Method
        TimeoutSec = 20
    }

    if ($AccessToken) {
        $Parameters.Headers = @{
            Authorization = "Bearer $AccessToken"
        }
    }

    if ($null -ne $Body) {
        $Parameters.ContentType = "application/json"
        $Parameters.Body = $Body | ConvertTo-Json -Depth 30
    }

    return Invoke-RestMethod @Parameters
}

function Get-HttpStatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ErrorRecord
    )

    if ($null -eq $ErrorRecord.Exception) {
        return $null
    }

    if ($null -eq $ErrorRecord.Exception.Response) {
        return $null
    }

    $Response = $ErrorRecord.Exception.Response
    $StatusProperty = $Response.PSObject.Properties["StatusCode"]

    if ($null -eq $StatusProperty) {
        return $null
    }

    try {
        return [int]$StatusProperty.Value
    }
    catch {
        $ValueProperty = $StatusProperty.Value.PSObject.Properties["value__"]

        if ($null -ne $ValueProperty) {
            return [int]$ValueProperty.Value
        }

        return $null
    }
}

function Assert-HttpStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [string]$AccessToken,

        [AllowNull()]
        [hashtable]$Body,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedStatus,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    try {
        $Parameters = @{
            Uri             = $Uri
            Method          = $Method
            TimeoutSec      = 20
            UseBasicParsing = $true
        }

        if ($AccessToken) {
            $Parameters.Headers = @{
                Authorization = "Bearer $AccessToken"
            }
        }

        if ($null -ne $Body) {
            $Parameters.ContentType = "application/json"
            $Parameters.Body = $Body | ConvertTo-Json -Depth 30
        }

        $Response = Invoke-WebRequest @Parameters
        $ActualStatus = [int]$Response.StatusCode

        if ($ActualStatus -ne $ExpectedStatus) {
            throw "$Description retornou HTTP $ActualStatus em vez de $ExpectedStatus."
        }

        Write-Host "[OK] $Description -> HTTP $ExpectedStatus" -ForegroundColor Green
        return
    }
    catch {
        $StatusCode = Get-HttpStatusCode -ErrorRecord $_

        if ($StatusCode -ne $ExpectedStatus) {
            Write-Host ""
            Write-Host "[ERROR] HTTP inesperado." -ForegroundColor Red
            Write-Host "Descricao: $Description"
            Write-Host "Esperado:  $ExpectedStatus"
            Write-Host "Recebido:  $StatusCode"

            throw
        }

        Write-Host "[OK] $Description -> HTTP $ExpectedStatus" -ForegroundColor Green
    }
}

function Get-PropertyValue {
    param(
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $Property = $Object.PSObject.Properties[$Name]

    if ($null -eq $Property) {
        return $null
    }

    return $Property.Value
}

function Get-ResponseItems {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [System.Array]) {
        foreach ($Entry in $Value) {
            Get-ResponseItems -Value $Entry
        }

        return
    }

    $ItemsProperty = $Value.PSObject.Properties["items"]

    if ($null -ne $ItemsProperty) {
        Get-ResponseItems -Value $ItemsProperty.Value
        return
    }

    $DataProperty = $Value.PSObject.Properties["data"]

    if ($null -ne $DataProperty) {
        Get-ResponseItems -Value $DataProperty.Value
        return
    }

    Write-Output -NoEnumerate $Value
}

function Test-CollectionContainsId {
    param(
        [AllowNull()]
        [object]$Collection,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    [object[]]$Items = @(
        Get-ResponseItems -Value $Collection
    )

    foreach ($Item in $Items) {
        $CurrentId = Get-PropertyValue -Object $Item -Name "id"

        if ($null -ne $CurrentId -and [string]$CurrentId -eq $Id) {
            return $true
        }
    }

    return $false
}

function Write-Document {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    Set-Content `
        -Path $Path `
        -Value $Lines `
        -Encoding UTF8
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

Set-Location $RepositoryRoot

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ETAPA 4 - MACROBLOCO 4.2" -ForegroundColor Cyan
Write-Host " MIGRATION + CI + RUNTIME + AUDITORIA" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ============================================================
# PREFLIGHT
# ============================================================

$RequiredFiles = @(
    ".\packages\validation\src\ads.ts",
    ".\packages\contracts\src\ads.ts",
    ".\apps\api\src\ads\ads.service.ts",
    ".\apps\api\src\ads\ads-requests.controller.ts",
    ".\apps\api\src\ads\ads-queue.controller.ts",
    ".\apps\api\src\ads\ads.module.ts"
)

foreach ($RequiredFile in $RequiredFiles) {
    if (-not (Test-Path $RequiredFile)) {
        throw "Macrobloco 4.1 incompleto. Arquivo ausente: $RequiredFile"
    }
}

$SchemaContent = Get-Content `
    ".\packages\database\prisma\schema.prisma" `
    -Raw

$RequiredSchemaMarkers = @(
    "enum AdsRequestStatus",
    "enum AdsQueueItemStatus",
    "model AdsRequest",
    "model AdsQueueItem"
)

foreach ($Marker in $RequiredSchemaMarkers) {
    if (-not $SchemaContent.Contains($Marker)) {
        throw "Schema Stage 4 incompleto: $Marker"
    }
}

Write-Host "[OK] Preflight Macrobloco 4.1." -ForegroundColor Green

# ============================================================
# DATABASE
# ============================================================

Invoke-NativeCommand `
    -Description "Prisma format" `
    -Command "pnpm" `
    -Arguments @("db:format")

Invoke-NativeCommand `
    -Description "Prisma validate" `
    -Command "pnpm" `
    -Arguments @("db:validate")

$MigrationRoot = ".\packages\database\prisma\migrations"

$ExistingMigration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_4_ads_requests_and_queue*"
    } |
    Select-Object -First 1

if ($null -eq $ExistingMigration) {
    Invoke-NativeCommand `
        -Description "Criar migration Stage 4" `
        -Command "pnpm" `
        -Arguments @(
            "--filter",
            "@crm/database",
            "exec",
            "prisma",
            "migrate",
            "dev",
            "--name",
            "stage_4_ads_requests_and_queue",
            "--create-only"
        )
}

$ExistingMigration = Get-ChildItem `
    -Path $MigrationRoot `
    -Directory `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*stage_4_ads_requests_and_queue*"
    } |
    Select-Object -First 1

if ($null -eq $ExistingMigration) {
    throw "Migration Stage 4 nao foi encontrada."
}

Write-Host "[OK] Migration encontrada: $($ExistingMigration.Name)" -ForegroundColor Green

Invoke-NativeCommand `
    -Description "Deploy migration Stage 4" `
    -Command "pnpm" `
    -Arguments @("db:migrate:deploy")

Invoke-NativeCommand `
    -Description "Prisma generate" `
    -Command "pnpm" `
    -Arguments @("db:generate")

Invoke-NativeCommand `
    -Description "Database seed Stage 4" `
    -Command "pnpm" `
    -Arguments @("db:seed")

Invoke-NativeCommand `
    -Description "Verify seed Stage 4" `
    -Command "pnpm" `
    -Arguments @("db:verify-seed")

Invoke-NativeCommand `
    -Description "Migration status" `
    -Command "pnpm" `
    -Arguments @("db:migrate:status")

# ============================================================
# FORMAT + CI
# ============================================================

Invoke-NativeCommand `
    -Description "Format repository" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-NativeCommand `
    -Description "Global CI Stage 4" `
    -Command "pnpm" `
    -Arguments @("ci:check")

# ============================================================
# RUNTIME CONFIG
# ============================================================

$Process = $null
$HadPreviousPort = Test-Path Env:PORT
$PreviousPort = $null

if ($HadPreviousPort) {
    $PreviousPort = $env:PORT
}

$env:PORT = [string]$SmokePort

$AdminPasswordSecure = Read-Host "Digite a senha do ADMIN" -AsSecureString
$EmployeePasswordSecure = Read-Host "Digite a senha do EMPLOYEE" -AsSecureString

$AdminPassword = ConvertTo-PlainText -Value $AdminPasswordSecure
$EmployeePassword = ConvertTo-PlainText -Value $EmployeePasswordSecure

$Timestamp = Get-Date -Format "yyyyMMddHHmmss"
$RandomBase = Get-Random -Minimum 1000000 -Maximum 9999999

$SiteSlug = "stage4-site-$Timestamp-$RandomBase"
$PoolSlug = "stage4-pool-$Timestamp-$RandomBase"
$EmptyPoolSlug = "stage4-empty-pool-$Timestamp-$RandomBase"

$Phone = "+55119$($RandomBase)4"

try {
    # ========================================================
    # START API
    # ========================================================

    Write-Host ""
    Write-Host "==== Stage 4 API runtime ====" -ForegroundColor Cyan

    $StartParameters = @{
        FilePath         = "node"
        ArgumentList     = "apps/api/dist/main.js"
        WorkingDirectory = $RepositoryRoot
        NoNewWindow      = $true
        PassThru         = $true
    }

    $Process = Start-Process @StartParameters

    $BaseUrl = "http://127.0.0.1:$SmokePort/api/v1"
    $Deadline = (Get-Date).AddSeconds(30)
    $Ready = $false

    while ((Get-Date) -lt $Deadline) {
        if ($null -ne $Process -and $Process.HasExited) {
            throw "API encerrou antes de ficar pronta. ExitCode: $($Process.ExitCode)"
        }

        try {
            $Health = Invoke-RestMethod `
                -Uri "$BaseUrl/health/ready" `
                -Method GET `
                -TimeoutSec 2

            $HealthStatus = Get-PropertyValue `
                -Object $Health `
                -Name "status"

            if ($HealthStatus -eq "ok") {
                $Ready = $true
                break
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $Ready) {
        throw "API Stage 4 nao ficou pronta."
    }

    Write-Host "[OK] API ready." -ForegroundColor Green

    # ========================================================
    # LOGIN
    # ========================================================

    Write-Host ""
    Write-Host "==== Login ====" -ForegroundColor Cyan

    $AdminLogin = Invoke-Json `
        -Uri "$BaseUrl/auth/login" `
        -Method POST `
        -Body @{
            email = "admin@example.com"
            organizationSlug = "crm-ads-whatsapp"
            password = $AdminPassword
        }

    $EmployeeLogin = Invoke-Json `
        -Uri "$BaseUrl/auth/login" `
        -Method POST `
        -Body @{
            email = "employee@example.com"
            organizationSlug = "crm-ads-whatsapp"
            password = $EmployeePassword
        }

    $AdminToken = [string](
        Get-PropertyValue `
            -Object $AdminLogin `
            -Name "accessToken"
    )

    $EmployeeToken = [string](
        Get-PropertyValue `
            -Object $EmployeeLogin `
            -Name "accessToken"
    )

    if ([string]::IsNullOrWhiteSpace($AdminToken)) {
        throw "ADMIN login nao retornou accessToken."
    }

    if ([string]::IsNullOrWhiteSpace($EmployeeToken)) {
        throw "EMPLOYEE login nao retornou accessToken."
    }

    Write-Host "[OK] ADMIN e EMPLOYEE autenticados." -ForegroundColor Green

    # ========================================================
    # AUTH BOUNDARY
    # ========================================================

    Write-Host ""
    Write-Host "==== Authentication boundary ====" -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/ads-requests" `
        -Method GET `
        -ExpectedStatus 401 `
        -Description "ADS requests sem token"

    Assert-HttpStatus `
        -Uri "$BaseUrl/ads-queue" `
        -Method GET `
        -ExpectedStatus 401 `
        -Description "ADS queue sem token"

    # ========================================================
    # FIXTURES
    # ========================================================

    Write-Host ""
    Write-Host "==== Stage 4 fixtures ====" -ForegroundColor Cyan

    $Site = Invoke-Json `
        -Uri "$BaseUrl/sites" `
        -Method POST `
        -AccessToken $AdminToken `
        -Body @{
            ownerEmployeeId = $EmployeeId
            name = "Stage 4 Site"
            slug = $SiteSlug
            description = "Stage 4 ADS runtime smoke"
        }

    $SiteId = [string](
        Get-PropertyValue `
            -Object $Site `
            -Name "id"
    )

    if ([string]::IsNullOrWhiteSpace($SiteId)) {
        throw "Site fixture nao retornou id."
    }

    $Number = Invoke-Json `
        -Uri "$BaseUrl/whatsapp-numbers" `
        -Method POST `
        -AccessToken $AdminToken `
        -Body @{
            displayName = "Stage 4 WhatsApp"
            e164 = $Phone
            assignedEmployeeId = $EmployeeId
            notes = "Stage 4 runtime smoke"
        }

    $NumberId = [string](
        Get-PropertyValue `
            -Object $Number `
            -Name "id"
    )

    if ([string]::IsNullOrWhiteSpace($NumberId)) {
        throw "WhatsApp fixture nao retornou id."
    }

    $Pool = Invoke-Json `
        -Uri "$BaseUrl/traffic-pools" `
        -Method POST `
        -AccessToken $AdminToken `
        -Body @{
            siteId = $SiteId
            name = "Stage 4 Traffic Pool"
            slug = $PoolSlug
            description = "Stage 4 runtime smoke"
        }

    $PoolId = [string](
        Get-PropertyValue `
            -Object $Pool `
            -Name "id"
    )

    if ([string]::IsNullOrWhiteSpace($PoolId)) {
        throw "Traffic Pool fixture nao retornou id."
    }

    $Member = Invoke-Json `
        -Uri "$BaseUrl/traffic-pools/$PoolId/members" `
        -Method POST `
        -AccessToken $AdminToken `
        -Body @{
            whatsAppNumberId = $NumberId
        }

    $MemberId = [string](
        Get-PropertyValue `
            -Object $Member `
            -Name "id"
    )

    if ([string]::IsNullOrWhiteSpace($MemberId)) {
        throw "Traffic Pool member fixture nao retornou id."
    }

    $EmptyPool = Invoke-Json `
        -Uri "$BaseUrl/traffic-pools" `
        -Method POST `
        -AccessToken $AdminToken `
        -Body @{
            siteId = $SiteId
            name = "Stage 4 Empty Pool"
            slug = $EmptyPoolSlug
            description = "Pool sem numero elegivel"
        }

    $EmptyPoolId = [string](
        Get-PropertyValue `
            -Object $EmptyPool `
            -Name "id"
    )

    if ([string]::IsNullOrWhiteSpace($EmptyPoolId)) {
        throw "Empty Traffic Pool fixture nao retornou id."
    }

    Write-Host "[OK] Fixtures Stage 4 preparadas." -ForegroundColor Green

    # ========================================================
    # VALIDATION
    # ========================================================

    Write-Host ""
    Write-Host "==== ADS validation ====" -ForegroundColor Cyan

    Assert-HttpStatus `
        -Uri "$BaseUrl/ads-requests" `
        -Method POST `
        -AccessToken $EmployeeToken `
        -Body @{
            siteId = $SiteId
            trafficPoolId = $PoolId
            requestedLeadCount = 0
        } `
        -ExpectedStatus 400 `
        -Description "requestedLeadCount zero"

    Assert-HttpStatus `
        -Uri "$BaseUrl/ads-requests" `
        -Method POST `
        -AccessToken $EmployeeToken `
        -Body @{
            siteId = $SiteId
            trafficPoolId = $PoolId
            requestedLeadCount = 100
            organizationId = "11111111-1111-4111-8111-111111111111"
        } `
        -ExpectedStatus 400 `
        -Description "tenant injection via payload"

    Assert-HttpStatus `
        -Uri "$BaseUrl/ads-requests" `
        -Method POST `
        -AccessToken $EmployeeToken `
        -Body @{
            siteId = $SiteId
            trafficPoolId = $EmptyPoolId
            requestedLeadCount = 100
        } `
        -ExpectedStatus 409 `
        -Description "Pool sem numero elegivel"

    # ========================================================
    # CREATE REQUEST
    # ========================================================

    Write-Host ""
    Write-Host "==== Create ADS Request + Queue ====" -ForegroundColor Cyan

    $AdsRequest = Invoke-Json `
        -Uri "$BaseUrl/ads-requests" `
        -Method POST `
        -AccessToken $EmployeeToken `
        -Body @{
            siteId = $SiteId
            trafficPoolId = $PoolId
            requestedLeadCount = 137
            notes = "Stage 4 smoke request"
        }

    $RequestId = [string](
        Get-PropertyValue `
            -Object $AdsRequest `
            -Name "id"
    )

    $RequestStatus = [string](
        Get-PropertyValue `
            -Object $AdsRequest `
            -Name "status"
    )

    $RequestEmployeeId = [string](
        Get-PropertyValue `
            -Object $AdsRequest `
            -Name "employeeId"
    )

    $QueueItem = Get-PropertyValue `
        -Object $AdsRequest `
        -Name "queueItem"

    $QueueItemId = [string](
        Get-PropertyValue `
            -Object $QueueItem `
            -Name "id"
    )

    $QueueStatus = [string](
        Get-PropertyValue `
            -Object $QueueItem `
            -Name "status"
    )

    if ([string]::IsNullOrWhiteSpace($RequestId)) {
        throw "ADS Request nao retornou id."
    }

    if ($RequestStatus -ne "QUEUED") {
        throw "ADS Request deveria iniciar QUEUED. Atual: $RequestStatus"
    }

    if ($RequestEmployeeId -ne $EmployeeId) {
        throw "ADS Request associado ao Employee incorreto."
    }

    if ([string]::IsNullOrWhiteSpace($QueueItemId)) {
        throw "ADS Request nao criou AdsQueueItem."
    }

    if ($QueueStatus -ne "WAITING") {
        throw "AdsQueueItem deveria iniciar WAITING. Atual: $QueueStatus"
    }

    Write-Host "[OK] Request QUEUED + Queue WAITING criados." -ForegroundColor Green

    # ========================================================
    # EMPLOYEE READ
    # ========================================================

    Write-Host ""
    Write-Host "==== EMPLOYEE ADS visibility ====" -ForegroundColor Cyan

    $EmployeeRequests = Invoke-Json `
        -Uri "$BaseUrl/ads-requests" `
        -Method GET `
        -AccessToken $EmployeeToken

    $EmployeeHasRequest = Test-CollectionContainsId `
        -Collection $EmployeeRequests `
        -Id $RequestId

    if (-not $EmployeeHasRequest) {
        throw "EMPLOYEE nao encontrou o proprio ADS Request."
    }

    $EmployeeRequest = Invoke-Json `
        -Uri "$BaseUrl/ads-requests/$RequestId" `
        -Method GET `
        -AccessToken $EmployeeToken

    $EmployeeRequestId = [string](
        Get-PropertyValue `
            -Object $EmployeeRequest `
            -Name "id"
    )

    if ($EmployeeRequestId -ne $RequestId) {
        throw "EMPLOYEE GET ADS Request retornou recurso inesperado."
    }

    $EmployeeQueue = Invoke-Json `
        -Uri "$BaseUrl/ads-queue" `
        -Method GET `
        -AccessToken $EmployeeToken

    $EmployeeHasQueueItem = Test-CollectionContainsId `
        -Collection $EmployeeQueue `
        -Id $QueueItemId

    if (-not $EmployeeHasQueueItem) {
        throw "EMPLOYEE nao encontrou o proprio queue item."
    }

    $EmployeeQueueItem = Invoke-Json `
        -Uri "$BaseUrl/ads-queue/$QueueItemId" `
        -Method GET `
        -AccessToken $EmployeeToken

    $EmployeeQueueId = [string](
        Get-PropertyValue `
            -Object $EmployeeQueueItem `
            -Name "id"
    )

    if ($EmployeeQueueId -ne $QueueItemId) {
        throw "EMPLOYEE GET queue item retornou recurso inesperado."
    }

    Write-Host "[OK] EMPLOYEE le request e queue do proprio escopo." -ForegroundColor Green

    # ========================================================
    # ADMIN READ
    # ========================================================

    Write-Host ""
    Write-Host "==== ADMIN ADS visibility ====" -ForegroundColor Cyan

    $AdminRequest = Invoke-Json `
        -Uri "$BaseUrl/ads-requests/$RequestId" `
        -Method GET `
        -AccessToken $AdminToken

    $AdminRequestId = [string](
        Get-PropertyValue `
            -Object $AdminRequest `
            -Name "id"
    )

    if ($AdminRequestId -ne $RequestId) {
        throw "ADMIN nao conseguiu ler ADS Request."
    }

    $AdminQueueItem = Invoke-Json `
        -Uri "$BaseUrl/ads-queue/$QueueItemId" `
        -Method GET `
        -AccessToken $AdminToken

    $AdminQueueItemId = [string](
        Get-PropertyValue `
            -Object $AdminQueueItem `
            -Name "id"
    )

    if ($AdminQueueItemId -ne $QueueItemId) {
        throw "ADMIN nao conseguiu ler queue item."
    }

    Write-Host "[OK] ADMIN possui visibilidade organizacional." -ForegroundColor Green

    # ========================================================
    # CANCEL
    # ========================================================

    Write-Host ""
    Write-Host "==== ADS cancellation lifecycle ====" -ForegroundColor Cyan

    $CancelledRequest = Invoke-Json `
        -Uri "$BaseUrl/ads-requests/$RequestId/cancel" `
        -Method POST `
        -AccessToken $EmployeeToken

    $CancelledRequestStatus = [string](
        Get-PropertyValue `
            -Object $CancelledRequest `
            -Name "status"
    )

    $CancelledQueue = Get-PropertyValue `
        -Object $CancelledRequest `
        -Name "queueItem"

    $CancelledQueueStatus = [string](
        Get-PropertyValue `
            -Object $CancelledQueue `
            -Name "status"
    )

    $RequestCancelledAt = Get-PropertyValue `
        -Object $CancelledRequest `
        -Name "cancelledAt"

    $QueueCancelledAt = Get-PropertyValue `
        -Object $CancelledQueue `
        -Name "cancelledAt"

    if ($CancelledRequestStatus -ne "CANCELLED") {
        throw "ADS Request nao mudou para CANCELLED."
    }

    if ($CancelledQueueStatus -ne "CANCELLED") {
        throw "AdsQueueItem nao mudou para CANCELLED."
    }

    if ($null -eq $RequestCancelledAt) {
        throw "ADS Request cancelledAt ausente."
    }

    if ($null -eq $QueueCancelledAt) {
        throw "AdsQueueItem cancelledAt ausente."
    }

    Write-Host "[OK] Request e queue cancelados transacionalmente." -ForegroundColor Green

    # ========================================================
    # IDEMPOTENT CANCEL
    # ========================================================

    $CancelledAgain = Invoke-Json `
        -Uri "$BaseUrl/ads-requests/$RequestId/cancel" `
        -Method POST `
        -AccessToken $EmployeeToken

    $CancelledAgainStatus = [string](
        Get-PropertyValue `
            -Object $CancelledAgain `
            -Name "status"
    )

    if ($CancelledAgainStatus -ne "CANCELLED") {
        throw "Segundo cancelamento deveria permanecer CANCELLED."
    }

    Write-Host "[OK] Cancelamento idempotente." -ForegroundColor Green

    $QueueAfterCancel = Invoke-Json `
        -Uri "$BaseUrl/ads-queue/$QueueItemId" `
        -Method GET `
        -AccessToken $EmployeeToken

    $QueueAfterCancelStatus = [string](
        Get-PropertyValue `
            -Object $QueueAfterCancel `
            -Name "status"
    )

    if ($QueueAfterCancelStatus -ne "CANCELLED") {
        throw "Queue item persistido nao permaneceu CANCELLED."
    }

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host "[OK] STAGE 4 RUNTIME SMOKE PASSED." -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
}
finally {
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process `
            -Id $Process.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($HadPreviousPort) {
        $env:PORT = $PreviousPort
    }

    if (-not $HadPreviousPort) {
        Remove-Item `
            Env:PORT `
            -ErrorAction SilentlyContinue
    }
}

# ============================================================
# TENANT STATIC AUDIT
# ============================================================

Write-Host ""
Write-Host "==== Tenant static audit ====" -ForegroundColor Cyan

$UnsafeTenantReferences = Get-ChildItem `
    ".\apps\api\src\ads" `
    -Filter "*.ts" `
    -Recurse |
    Select-String `
        -Pattern "input\.organizationId|body\.organizationId|parsed\.data\.organizationId"

if ($UnsafeTenantReferences) {
    Write-Host "[ERROR] Possivel tenant injection:" -ForegroundColor Red
    $UnsafeTenantReferences
    throw "Tenant audit falhou."
}

Write-Host "[OK] organizationId nao e derivado do payload." -ForegroundColor Green

# ============================================================
# DOCUMENTATION
# No here-strings. Arrays only.
# ============================================================

Write-Host ""
Write-Host "==== Stage 4 documentation ====" -ForegroundColor Cyan

$Stage4Document = @(
    "# Etapa 4 - ADS Requests + Persistent Queue",
    "",
    "## Status",
    "",
    "CONCLUIDA.",
    "",
    "## Objetivo",
    "",
    "Implementar pedidos persistentes de ADS e sua entrada em uma fila de dominio recuperavel.",
    "",
    "A Etapa 4 nao executa distribuicao de leads. A execucao pertence a Etapa 5.",
    "",
    "## AdsRequest",
    "",
    "Campos principais:",
    "",
    "- organizationId",
    "- employeeId",
    "- siteId",
    "- trafficPoolId",
    "- requestedByUserId",
    "- requestedLeadCount",
    "- fulfilledLeadCount",
    "- status",
    "- queuedAt",
    "- startedAt",
    "- completedAt",
    "- cancelledAt",
    "- failureReason",
    "",
    "Status preparados:",
    "",
    "- QUEUED",
    "- PROCESSING",
    "- PARTIALLY_FULFILLED",
    "- FULFILLED",
    "- CANCELLED",
    "- FAILED",
    "",
    "## AdsQueueItem",
    "",
    "Status:",
    "",
    "- WAITING",
    "- CLAIMED",
    "- COMPLETED",
    "- CANCELLED",
    "- FAILED",
    "",
    "## Fonte de verdade",
    "",
    "PostgreSQL e a fonte de verdade do estado da fila.",
    "",
    "BullMQ podera ser utilizado na Etapa 5 para execucao assincrona.",
    "",
    "## Criacao transacional",
    "",
    "A mesma transacao cria:",
    "",
    "1. AdsRequest QUEUED",
    "2. AdsQueueItem WAITING",
    "3. AuditLog ads_request.created",
    "4. AuditLog ads_queue.enqueued",
    "",
    "## Eligibility",
    "",
    "- Organization precisa corresponder ao principal autenticado.",
    "- Employee precisa estar ACTIVE.",
    "- Site precisa estar ACTIVE.",
    "- Site precisa pertencer ao Employee.",
    "- Traffic Pool precisa pertencer ao Site.",
    "- Traffic Pool precisa estar ACTIVE.",
    "- Deve existir TrafficPoolMember ACTIVE.",
    "- WhatsAppNumber precisa estar ACTIVE.",
    "- Numero precisa estar atribuido ao owner do Site.",
    "",
    "## Permissions",
    "",
    "Total: 23 permissions.",
    "",
    "EMPLOYEE: 9 permissions.",
    "",
    "EMPLOYEE recebe:",
    "",
    "- ads_request.read",
    "- ads_request.manage",
    "- ads_queue.read",
    "",
    "EMPLOYEE nao recebe ads_queue.manage.",
    "",
    "## Endpoints",
    "",
    "- GET /api/v1/ads-requests",
    "- GET /api/v1/ads-requests/:requestId",
    "- POST /api/v1/ads-requests",
    "- POST /api/v1/ads-requests/:requestId/cancel",
    "- GET /api/v1/ads-queue",
    "- GET /api/v1/ads-queue/:queueItemId",
    "",
    "## Cancelamento",
    "",
    "AdsRequest: QUEUED -> CANCELLED",
    "",
    "AdsQueueItem: WAITING -> CANCELLED",
    "",
    "Cancelamento repetido e idempotente.",
    "",
    "## Queue ordering",
    "",
    "1. priority",
    "2. availableAt",
    "3. enqueuedAt",
    "4. id",
    "",
    "## Runtime smoke",
    "",
    "- rotas sem token -> 401",
    "- payload invalido -> 400",
    "- tenant injection -> 400",
    "- pool sem numero elegivel -> 409",
    "- EMPLOYEE cria pedido proprio",
    "- request inicia QUEUED",
    "- queue inicia WAITING",
    "- EMPLOYEE le request e queue proprios",
    "- ADMIN possui leitura organizacional",
    "- cancelamento request + queue",
    "- cancelledAt persistido",
    "- cancelamento idempotente",
    "",
    "## Fora do escopo",
    "",
    "- scheduler",
    "- claim",
    "- lease",
    "- microbatches",
    "- round-robin",
    "- backpressure",
    "- overflow",
    "- lead delivery",
    "- Meta transport",
    "",
    "## Proxima etapa",
    "",
    "Etapa 5 - Scheduler, microlotes, round-robin e backpressure."
)

Write-Document `
    -Path ".\docs\ETAPA_4_ADS_REQUESTS_QUEUE.md" `
    -Lines $Stage4Document

$DecisionsDocument = @(
    "# Decisoes - Etapa 4",
    "",
    "## Fila persistente",
    "",
    "PostgreSQL e a fonte de verdade do estado da fila.",
    "",
    "BullMQ podera atuar como mecanismo de execucao na Etapa 5.",
    "",
    "## Relacao",
    "",
    "Cada AdsRequest possui no maximo um AdsQueueItem.",
    "",
    "## Ownership",
    "",
    "AdsRequest pertence a Organization, Employee, Site, TrafficPool e requesting User.",
    "",
    "## Employee",
    "",
    "EMPLOYEE cria pedidos somente para os proprios Sites e Traffic Pools.",
    "",
    "employeeId nao e aceito como autoridade pelo body.",
    "",
    "## Queue ordering",
    "",
    "priority -> availableAt -> enqueuedAt -> id",
    "",
    "## Eligibility",
    "",
    "Pedido entra na fila somente quando existe numero elegivel no Traffic Pool.",
    "",
    "Indisponibilidade posterior pertence ao scheduler e backpressure da Etapa 5.",
    "",
    "## Cancelamento",
    "",
    "Etapa 4:",
    "",
    "QUEUED -> CANCELLED",
    "",
    "WAITING -> CANCELLED",
    "",
    "## Limits",
    "",
    "requestedLeadCount minimo: 1",
    "",
    "requestedLeadCount maximo: 100000",
    "",
    "## Proxima etapa",
    "",
    "- scheduler",
    "- claim e lease",
    "- microbatches",
    "- round-robin",
    "- backpressure",
    "- overflow",
    "- progress",
    "- completion e failure"
)

Write-Document `
    -Path ".\docs\DECISOES_ETAPA_4.md" `
    -Lines $DecisionsDocument

$EtapasPath = ".\docs\ETAPAS.md"

if (Test-Path $EtapasPath) {
    $EtapasContent = Get-Content `
        -Path $EtapasPath `
        -Raw

    $Stage4Marker = "## Etapa 4 - ADS Requests + Queue"

    if (-not $EtapasContent.Contains($Stage4Marker)) {
        $Stage4Summary = @(
            "",
            "## Etapa 4 - ADS Requests + Queue",
            "",
            "Status: CONCLUIDA.",
            "",
            "Implementado:",
            "",
            "- AdsRequest",
            "- AdsQueueItem",
            "- fila persistente PostgreSQL",
            "- criacao transacional",
            "- eligibility",
            "- cancelamento transacional",
            "- ADMIN/EMPLOYEE isolation",
            "- 23 permissions totais",
            "- EMPLOYEE com 9 permissions",
            "- runtime smoke",
            "- tenant audit",
            "- CI global",
            "",
            "Documentacao:",
            "",
            "- docs/ETAPA_4_ADS_REQUESTS_QUEUE.md",
            "- docs/DECISOES_ETAPA_4.md",
            "",
            "Proxima:",
            "",
            "- Etapa 5 - Scheduler, microlotes, round-robin e backpressure."
        )

        Add-Content `
            -Path $EtapasPath `
            -Value $Stage4Summary `
            -Encoding UTF8
    }
}

Write-Host "[OK] Documentacao Stage 4 criada." -ForegroundColor Green

# ============================================================
# FINAL FORMAT
# ============================================================

Invoke-NativeCommand `
    -Description "Final format" `
    -Command "pnpm" `
    -Arguments @("format")

Invoke-NativeCommand `
    -Description "Final format check" `
    -Command "pnpm" `
    -Arguments @("format:check")

# ============================================================
# GIT DIFF CHECK
# ============================================================

Write-Host ""
Write-Host "==== Git diff check ====" -ForegroundColor Cyan

& git diff --check

if ($LASTEXITCODE -ne 0) {
    throw "git diff --check falhou."
}

Write-Host "[OK] git diff --check." -ForegroundColor Green

# ============================================================
# TRACKED ENV CHECK
# ============================================================

Write-Host ""
Write-Host "==== Tracked environment files ====" -ForegroundColor Cyan

[string[]]$TrackedFiles = @(
    & git ls-files
)

if ($LASTEXITCODE -ne 0) {
    throw "git ls-files falhou."
}

[string[]]$TrackedEnvFiles = @(
    $TrackedFiles |
    Where-Object {
        $_ -match '(^|/)\.env($|\.)' -and
        $_ -notmatch '\.env\.example$'
    }
)

if (@($TrackedEnvFiles).Count -gt 0) {
    Write-Host "[ERROR] .env real versionado:" -ForegroundColor Red
    $TrackedEnvFiles
    throw "Arquivo de ambiente real versionado."
}

Write-Host "[OK] Nenhum .env real versionado." -ForegroundColor Green

# ============================================================
# SECRET SCAN
# ============================================================

Write-Host ""
Write-Host "==== Secret scan ====" -ForegroundColor Cyan

$SecretPattern = 'sk-proj-|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY'

[string[]]$SecretMatches = @(
    & git grep `
        -n `
        -I `
        -E `
        $SecretPattern `
        2>$null
)

$SecretExitCode = $LASTEXITCODE

if ($SecretExitCode -ne 0 -and $SecretExitCode -ne 1) {
    throw "git grep falhou durante secret scan."
}

if (@($SecretMatches).Count -gt 0) {
    Write-Host "[ERROR] Possivel segredo encontrado:" -ForegroundColor Red
    $SecretMatches
    throw "Secret scan falhou."
}

Write-Host "[OK] Nenhum segredo obvio encontrado." -ForegroundColor Green

# ============================================================
# STATUS
# ============================================================

Write-Host ""
Write-Host "==== Git status ====" -ForegroundColor Cyan

& git status --short

if ($LASTEXITCODE -ne 0) {
    throw "git status falhou."
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "[OK] ETAPA 4 COMPLETAMENTE VALIDADA." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Validado:" -ForegroundColor Cyan
Write-Host "- Prisma schema"
Write-Host "- migration"
Write-Host "- database deploy"
Write-Host "- seed 23 permissions"
Write-Host "- EMPLOYEE 9 permissions"
Write-Host "- global CI"
Write-Host "- ADS Request runtime"
Write-Host "- persistent queue runtime"
Write-Host "- eligibility"
Write-Host "- tenant injection"
Write-Host "- ADMIN/EMPLOYEE visibility"
Write-Host "- cancellation"
Write-Host "- idempotency"
Write-Host "- tenant static audit"
Write-Host "- documentation"
Write-Host "- git diff"
Write-Host "- env scan"
Write-Host "- secret scan"
Write-Host ""
Write-Host "Proxima etapa: ETAPA 5." -ForegroundColor Yellow