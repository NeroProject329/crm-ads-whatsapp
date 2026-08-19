param(
    [Parameter(Mandatory = $true)]
    [string]$EmployeeId,

    [int]$SmokePort = 3107
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$EmployeeId = $EmployeeId.Trim()

if (
    $EmployeeId -notmatch
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
) {
    throw "EmployeeId invalido. Informe employee.id em formato UUID."
}

function ConvertTo-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$Value
    )

    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $Value
    )

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            $Pointer
        )
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            $Pointer
        )
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
        TimeoutSec = 15
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

    if (
        $null -eq $ErrorRecord.Exception
    ) {
        return $null
    }

    if (
        $null -eq $ErrorRecord.Exception.Response
    ) {
        return $null
    }

    $Response = $ErrorRecord.Exception.Response

    $StatusCodeProperty = $Response.PSObject.Properties['StatusCode']

    if ($null -eq $StatusCodeProperty) {
        return $null
    }

    try {
        return [int]$StatusCodeProperty.Value
    }
    catch {
        $ValueProperty = $StatusCodeProperty.Value.PSObject.Properties['value__']

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
            TimeoutSec      = 15
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
            throw "$Description returned HTTP $ActualStatus instead of $ExpectedStatus."
        }

        Write-Host "[OK] $Description returned HTTP $ExpectedStatus." -ForegroundColor Green
    }
    catch {
        $StatusCode = Get-HttpStatusCode -ErrorRecord $_

        if ($StatusCode -ne $ExpectedStatus) {
            Write-Host ""
            Write-Host "[ERROR] Unexpected HTTP response." -ForegroundColor Red
            Write-Host "Description: $Description"
            Write-Host "Expected:    $ExpectedStatus"
            Write-Host "Received:    $StatusCode"

            throw
        }

        Write-Host "[OK] $Description returned HTTP $ExpectedStatus." -ForegroundColor Green
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

    $ItemsProperty = $Value.PSObject.Properties['items']

    if ($null -ne $ItemsProperty) {
        Get-ResponseItems -Value $ItemsProperty.Value
        return
    }

    $DataProperty = $Value.PSObject.Properties['data']

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

    [object[]]$Items = @(Get-ResponseItems -Value $Collection)

    foreach ($Item in $Items) {
        $CurrentId = Get-PropertyValue -Object $Item -Name "id"

        if (
            $null -ne $CurrentId -and
            [string]$CurrentId -eq $Id
        ) {
            return $true
        }
    }

    return $false
}

function Find-CollectionItemById {
    param(
        [AllowNull()]
        [object]$Collection,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    [object[]]$Items = @(Get-ResponseItems -Value $Collection)

    foreach ($Item in $Items) {
        $CurrentId = Get-PropertyValue -Object $Item -Name "id"

        if (
            $null -ne $CurrentId -and
            [string]$CurrentId -eq $Id
        ) {
            return $Item
        }
    }

    return $null
}

function Write-JsonDebug {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [AllowNull()]
        [object]$Value
    )

    Write-Host ""
    Write-Host "[DEBUG] $Title" -ForegroundColor Yellow

    if ($null -eq $Value) {
        Write-Host "<null>"
        return
    }

    $Value |
        ConvertTo-Json -Depth 30 |
        Write-Host
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

Set-Location $RepositoryRoot

$AdminPassword = $null
$EmployeePassword = $null
$Process = $null

$HadPreviousPort = Test-Path Env:PORT

if ($HadPreviousPort) {
    $PreviousPort = $env:PORT
}
else {
    $PreviousPort = $null
}

$env:PORT = [string]$SmokePort

$AdminPasswordSecure = Read-Host "Digite a senha do ADMIN" -AsSecureString
$EmployeePasswordSecure = Read-Host "Digite a senha do EMPLOYEE" -AsSecureString

$AdminPassword = ConvertTo-PlainText -Value $AdminPasswordSecure
$EmployeePassword = ConvertTo-PlainText -Value $EmployeePasswordSecure

$Timestamp = Get-Date -Format "yyyyMMddHHmmss"
$RandomBase = Get-Random -Minimum 1000000 -Maximum 9999999

$SiteSlug = "stage3c-site-$Timestamp-$RandomBase"
$PoolSlug = "stage3c-pool-$Timestamp-$RandomBase"
$ForbiddenPoolSlug = "stage3c-forbidden-$Timestamp-$RandomBase"

$Phone1 = "+55119$($RandomBase)1"
$Phone2 = "+55119$($RandomBase)2"
$Phone3 = "+55119$($RandomBase)3"

try {
    Write-Host ""
    Write-Host "==== Stage 3C runtime build ====" -ForegroundColor Cyan

    pnpm exec turbo run build --filter="@crm/api"

    if ($LASTEXITCODE -ne 0) {
        throw "API build failed."
    }

    $StartProcessParameters = @{
        FilePath        = "node"
        ArgumentList    = "apps/api/dist/main.js"
        WorkingDirectory = $RepositoryRoot
        NoNewWindow     = $true
        PassThru        = $true
    }

    $Process = Start-Process @StartProcessParameters

    $BaseUrl = "http://127.0.0.1:$SmokePort/api/v1"
    $Deadline = (Get-Date).AddSeconds(25)
    $Ready = $false

    while ((Get-Date) -lt $Deadline) {
        if (
            $null -ne $Process -and
            $Process.HasExited
        ) {
            throw "API process exited before becoming ready. ExitCode: $($Process.ExitCode)"
        }

        try {
            $Health = Invoke-RestMethod -Uri "$BaseUrl/health/ready" -Method GET -TimeoutSec 2

            $HealthStatus = Get-PropertyValue -Object $Health -Name "status"

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
        throw "API did not become ready."
    }

    Write-Host "[OK] API ready." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== Login ====" -ForegroundColor Cyan

    $AdminLogin = Invoke-Json -Uri "$BaseUrl/auth/login" -Method POST -Body @{
        email            = "admin@example.com"
        organizationSlug = "crm-ads-whatsapp"
        password         = $AdminPassword
    }

    $EmployeeLogin = Invoke-Json -Uri "$BaseUrl/auth/login" -Method POST -Body @{
        email            = "employee@example.com"
        organizationSlug = "crm-ads-whatsapp"
        password         = $EmployeePassword
    }

    $AdminToken = [string](Get-PropertyValue -Object $AdminLogin -Name "accessToken")
    $EmployeeToken = [string](Get-PropertyValue -Object $EmployeeLogin -Name "accessToken")

    if ([string]::IsNullOrWhiteSpace($AdminToken)) {
        throw "ADMIN login did not return accessToken."
    }

    if ([string]::IsNullOrWhiteSpace($EmployeeToken)) {
        throw "EMPLOYEE login did not return accessToken."
    }

    Write-Host "[OK] ADMIN and EMPLOYEE authenticated." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== Site fixture ====" -ForegroundColor Cyan

    $Site = Invoke-Json -Uri "$BaseUrl/sites" -Method POST -AccessToken $AdminToken -Body @{
        ownerEmployeeId = $EmployeeId
        name            = "Stage 3C Traffic Site"
        slug            = $SiteSlug
        description     = "Stage 3C runtime validation"
    }

    $SiteId = [string](Get-PropertyValue -Object $Site -Name "id")
    $SiteOwnerEmployeeId = [string](Get-PropertyValue -Object $Site -Name "ownerEmployeeId")

    if ([string]::IsNullOrWhiteSpace($SiteId)) {
        Write-JsonDebug -Title "Site creation response" -Value $Site
        throw "Site creation did not return id."
    }

    if ($SiteOwnerEmployeeId -ne $EmployeeId) {
        Write-JsonDebug -Title "Site creation response" -Value $Site
        throw "Site ownership fixture is invalid."
    }

    Write-Host "[OK] Site created for EMPLOYEE." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== WhatsApp number fixtures ====" -ForegroundColor Cyan

    $Number1 = Invoke-Json -Uri "$BaseUrl/whatsapp-numbers" -Method POST -AccessToken $AdminToken -Body @{
        displayName       = "Stage 3C WhatsApp 01"
        e164              = $Phone1
        assignedEmployeeId = $EmployeeId
    }

    $Number2 = Invoke-Json -Uri "$BaseUrl/whatsapp-numbers" -Method POST -AccessToken $AdminToken -Body @{
        displayName       = "Stage 3C WhatsApp 02"
        e164              = $Phone2
        assignedEmployeeId = $EmployeeId
    }

    $Number3 = Invoke-Json -Uri "$BaseUrl/whatsapp-numbers" -Method POST -AccessToken $AdminToken -Body @{
        displayName = "Stage 3C WhatsApp Invalid Eligibility"
        e164        = $Phone3
    }

    $Number1Id = [string](Get-PropertyValue -Object $Number1 -Name "id")
    $Number2Id = [string](Get-PropertyValue -Object $Number2 -Name "id")
    $Number3Id = [string](Get-PropertyValue -Object $Number3 -Name "id")

    if (
        [string]::IsNullOrWhiteSpace($Number1Id) -or
        [string]::IsNullOrWhiteSpace($Number2Id) -or
        [string]::IsNullOrWhiteSpace($Number3Id)
    ) {
        throw "One or more WhatsApp fixtures did not return id."
    }

    Write-Host "[OK] Two eligible numbers and one unassigned number created." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== Traffic Pool creation ====" -ForegroundColor Cyan

    $Pool = Invoke-Json -Uri "$BaseUrl/traffic-pools" -Method POST -AccessToken $AdminToken -Body @{
        siteId      = $SiteId
        name        = "Stage 3C Main Pool"
        slug        = $PoolSlug
        description = "Runtime pool validation"
    }

    $PoolId = [string](Get-PropertyValue -Object $Pool -Name "id")
    $PoolSiteId = [string](Get-PropertyValue -Object $Pool -Name "siteId")

    if ([string]::IsNullOrWhiteSpace($PoolId)) {
        Write-JsonDebug -Title "Traffic Pool creation response" -Value $Pool
        throw "Traffic Pool creation did not return id."
    }

    if ($PoolSiteId -ne $SiteId) {
        Write-JsonDebug -Title "Traffic Pool creation response" -Value $Pool
        throw "Traffic Pool was created for unexpected site."
    }

    Write-Host "[OK] ADMIN created Traffic Pool." -ForegroundColor Green

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools" -Method POST -AccessToken $AdminToken -ExpectedStatus 409 -Description "Duplicate Traffic Pool slug" -Body @{
        siteId = $SiteId
        name   = "Duplicate Traffic Pool"
        slug   = $PoolSlug
    }

    Write-Host ""
    Write-Host "==== Membership eligibility ====" -ForegroundColor Cyan

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method POST -AccessToken $AdminToken -ExpectedStatus 409 -Description "Unassigned number entering Traffic Pool" -Body @{
        whatsAppNumberId = $Number3Id
    }

    $Number3Assigned = Invoke-Json -Uri "$BaseUrl/whatsapp-numbers/$Number3Id" -Method PATCH -AccessToken $AdminToken -Body @{
        assignedEmployeeId = $EmployeeId
        status             = "PAUSED"
    }

    $Number3Status = [string](Get-PropertyValue -Object $Number3Assigned -Name "status")

    if ($Number3Status -ne "PAUSED") {
        Write-JsonDebug -Title "Number 3 PATCH response" -Value $Number3Assigned
        throw "Number 3 fixture was not paused."
    }

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method POST -AccessToken $AdminToken -ExpectedStatus 409 -Description "PAUSED number entering Traffic Pool" -Body @{
        whatsAppNumberId = $Number3Id
    }

    Write-Host "[OK] Membership eligibility rules validated." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== Add eligible members ====" -ForegroundColor Cyan

    $Member1 = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method POST -AccessToken $AdminToken -Body @{
        whatsAppNumberId = $Number1Id
    }

    $Member1Id = [string](Get-PropertyValue -Object $Member1 -Name "id")
    $Member1Position = [int](Get-PropertyValue -Object $Member1 -Name "position")

    if ([string]::IsNullOrWhiteSpace($Member1Id)) {
        Write-JsonDebug -Title "First member response" -Value $Member1
        throw "First Traffic Pool member did not return id."
    }

    if ($Member1Position -ne 1) {
        Write-JsonDebug -Title "First member response" -Value $Member1
        throw "First Traffic Pool member should have position 1."
    }

    $Member2 = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method POST -AccessToken $AdminToken -Body @{
        whatsAppNumberId = $Number2Id
    }

    $Member2Id = [string](Get-PropertyValue -Object $Member2 -Name "id")
    $Member2Position = [int](Get-PropertyValue -Object $Member2 -Name "position")

    if ([string]::IsNullOrWhiteSpace($Member2Id)) {
        Write-JsonDebug -Title "Second member response" -Value $Member2
        throw "Second Traffic Pool member did not return id."
    }

    if ($Member2Position -ne 2) {
        Write-JsonDebug -Title "Second member response" -Value $Member2
        throw "Second Traffic Pool member should have position 2."
    }

    Write-Host "[OK] First member assigned position 1." -ForegroundColor Green
    Write-Host "[OK] Second member assigned position 2." -ForegroundColor Green

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method POST -AccessToken $AdminToken -ExpectedStatus 409 -Description "Duplicate Traffic Pool membership" -Body @{
        whatsAppNumberId = $Number1Id
    }

    Write-Host ""
    Write-Host "==== EMPLOYEE read boundary ====" -ForegroundColor Cyan

    $EmployeePoolsResponse = Invoke-Json -Uri "$BaseUrl/traffic-pools" -Method GET -AccessToken $EmployeeToken
    [object[]]$EmployeePools = @(
        Get-ResponseItems -Value $EmployeePoolsResponse
    )

    if (
        -not (
            Test-CollectionContainsId -Collection $EmployeePools -Id $PoolId
        )
    ) {
        Write-JsonDebug -Title "EMPLOYEE Traffic Pool list" -Value $EmployeePoolsResponse
        throw "EMPLOYEE cannot see Traffic Pool from own site."
    }

    Write-Host "[OK] EMPLOYEE sees Traffic Pool from own Site." -ForegroundColor Green

    $EmployeePool = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId" -Method GET -AccessToken $EmployeeToken
    $EmployeePoolId = [string](Get-PropertyValue -Object $EmployeePool -Name "id")

    if ($EmployeePoolId -ne $PoolId) {
        Write-JsonDebug -Title "EMPLOYEE Traffic Pool detail" -Value $EmployeePool
        throw "EMPLOYEE received unexpected Traffic Pool."
    }

    $EmployeeMembersResponse = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method GET -AccessToken $EmployeeToken
    [object[]]$EmployeeMembers = @(
        Get-ResponseItems -Value $EmployeeMembersResponse
    )

    if (
        -not (
            Test-CollectionContainsId -Collection $EmployeeMembers -Id $Member1Id
        )
    ) {
        Write-JsonDebug -Title "EMPLOYEE member list" -Value $EmployeeMembersResponse
        throw "EMPLOYEE cannot see first Traffic Pool member."
    }

    if (
        -not (
            Test-CollectionContainsId -Collection $EmployeeMembers -Id $Member2Id
        )
    ) {
        Write-JsonDebug -Title "EMPLOYEE member list" -Value $EmployeeMembersResponse
        throw "EMPLOYEE cannot see second Traffic Pool member."
    }

    Write-Host "[OK] EMPLOYEE can read pool and memberships." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== EMPLOYEE write restrictions ====" -ForegroundColor Cyan

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools" -Method POST -AccessToken $EmployeeToken -ExpectedStatus 403 -Description "EMPLOYEE creating Traffic Pool" -Body @{
        siteId = $SiteId
        name   = "Forbidden Pool"
        slug   = $ForbiddenPoolSlug
    }

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools/$PoolId" -Method PATCH -AccessToken $EmployeeToken -ExpectedStatus 403 -Description "EMPLOYEE updating Traffic Pool" -Body @{
        name = "Forbidden Update"
    }

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method POST -AccessToken $EmployeeToken -ExpectedStatus 403 -Description "EMPLOYEE adding Traffic Pool member" -Body @{
        whatsAppNumberId = $Number3Id
    }

    Assert-HttpStatus -Uri "$BaseUrl/traffic-pools/$PoolId/members/order" -Method PUT -AccessToken $EmployeeToken -ExpectedStatus 403 -Description "EMPLOYEE reordering Traffic Pool" -Body @{
        memberIds = @(
            $Member2Id,
            $Member1Id
        )
    }

    Write-Host ""
    Write-Host "==== Deterministic member reordering ====" -ForegroundColor Cyan

    $ReorderedResponse = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId/members/order" -Method PUT -AccessToken $AdminToken -Body @{
        memberIds = @(
            $Member2Id,
            $Member1Id
        )
    }

    [object[]]$Reordered = @(
        Get-ResponseItems -Value $ReorderedResponse
    )

    if ($Reordered.Count -ne 2) {
        Write-JsonDebug -Title "Reorder raw response" -Value $ReorderedResponse
        Write-Host "[DEBUG] Normalized item count: $($Reordered.Count)" -ForegroundColor Yellow
        throw "Reorder should return exactly two members."
    }

    $ReorderedMember1 = Find-CollectionItemById -Collection $Reordered -Id $Member1Id
    $ReorderedMember2 = Find-CollectionItemById -Collection $Reordered -Id $Member2Id

    if ($null -eq $ReorderedMember1) {
        Write-JsonDebug -Title "Reorder response" -Value $ReorderedResponse
        throw "Member 1 was not returned after reorder."
    }

    if ($null -eq $ReorderedMember2) {
        Write-JsonDebug -Title "Reorder response" -Value $ReorderedResponse
        throw "Member 2 was not returned after reorder."
    }

    $ReorderedMember1Position = [int](Get-PropertyValue -Object $ReorderedMember1 -Name "position")
    $ReorderedMember2Position = [int](Get-PropertyValue -Object $ReorderedMember2 -Name "position")

    if ($ReorderedMember2Position -ne 1) {
        Write-JsonDebug -Title "Reorder response" -Value $ReorderedResponse
        throw "Member 2 should have position 1 after reorder."
    }

    if ($ReorderedMember1Position -ne 2) {
        Write-JsonDebug -Title "Reorder response" -Value $ReorderedResponse
        throw "Member 1 should have position 2 after reorder."
    }

    [object[]]$OrderedReordered = @(
        $Reordered |
            Sort-Object {
                [int](Get-PropertyValue -Object $_ -Name "position")
            }
    )

    if ($OrderedReordered.Count -ne 2) {
        throw "Unexpected reorder normalization failure."
    }

    $FirstReorderedId = [string](Get-PropertyValue -Object $OrderedReordered[0] -Name "id")
    $SecondReorderedId = [string](Get-PropertyValue -Object $OrderedReordered[1] -Name "id")

    if (
        $FirstReorderedId -ne $Member2Id -or
        $SecondReorderedId -ne $Member1Id
    ) {
        Write-JsonDebug -Title "Reorder response" -Value $ReorderedResponse
        throw "Traffic Pool member order is inconsistent after reorder."
    }

    Write-Host "[OK] Member order changed from 1-2 to 2-1." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== Membership status ====" -ForegroundColor Cyan

    $PausedMember = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId/members/$Member1Id" -Method PATCH -AccessToken $AdminToken -Body @{
        status = "PAUSED"
    }

    $PausedMemberStatus = [string](Get-PropertyValue -Object $PausedMember -Name "status")

    if ($PausedMemberStatus -ne "PAUSED") {
        Write-JsonDebug -Title "Paused member response" -Value $PausedMember
        throw "Traffic Pool member was not paused."
    }

    Write-Host "[OK] ADMIN paused individual membership." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== Member removal and position compaction ====" -ForegroundColor Cyan

    $Removed = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId/members/$Member2Id" -Method DELETE -AccessToken $AdminToken

    $RemovedSuccess = Get-PropertyValue -Object $Removed -Name "success"

    if ($RemovedSuccess -ne $true) {
        Write-JsonDebug -Title "Member removal response" -Value $Removed
        throw "Traffic Pool member removal failed."
    }

    $RemainingMembersResponse = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId/members" -Method GET -AccessToken $AdminToken
    [object[]]$RemainingMembers = @(
        Get-ResponseItems -Value $RemainingMembersResponse
    )

    if ($RemainingMembers.Count -ne 1) {
        Write-JsonDebug -Title "Remaining members response" -Value $RemainingMembersResponse
        Write-Host "[DEBUG] Normalized item count: $($RemainingMembers.Count)" -ForegroundColor Yellow
        throw "Traffic Pool should contain exactly one member after removal."
    }

    $RemainingMember = Find-CollectionItemById -Collection $RemainingMembers -Id $Member1Id

    if ($null -eq $RemainingMember) {
        Write-JsonDebug -Title "Remaining members response" -Value $RemainingMembersResponse
        throw "Unexpected member remained after removal."
    }

    $RemainingPosition = [int](Get-PropertyValue -Object $RemainingMember -Name "position")
    $RemainingStatus = [string](Get-PropertyValue -Object $RemainingMember -Name "status")

    if ($RemainingPosition -ne 1) {
        Write-JsonDebug -Title "Remaining members response" -Value $RemainingMembersResponse
        throw "Remaining member position was not compacted to 1."
    }

    if ($RemainingStatus -ne "PAUSED") {
        Write-JsonDebug -Title "Remaining members response" -Value $RemainingMembersResponse
        throw "Remaining member status changed unexpectedly."
    }

    Write-Host "[OK] ADMIN removed position-1 member." -ForegroundColor Green
    Write-Host "[OK] Remaining member position compacted to 1." -ForegroundColor Green
    Write-Host "[OK] Membership status persisted after compaction." -ForegroundColor Green

    Write-Host ""
    Write-Host "==== Traffic Pool status management ====" -ForegroundColor Cyan

    $PausedPool = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId" -Method PATCH -AccessToken $AdminToken -Body @{
        status = "PAUSED"
    }

    $PausedPoolStatus = [string](Get-PropertyValue -Object $PausedPool -Name "status")

    if ($PausedPoolStatus -ne "PAUSED") {
        Write-JsonDebug -Title "Paused pool response" -Value $PausedPool
        throw "Traffic Pool was not paused."
    }

    $ActivePool = Invoke-Json -Uri "$BaseUrl/traffic-pools/$PoolId" -Method PATCH -AccessToken $AdminToken -Body @{
        status = "ACTIVE"
    }

    $ActivePoolStatus = [string](Get-PropertyValue -Object $ActivePool -Name "status")

    if ($ActivePoolStatus -ne "ACTIVE") {
        Write-JsonDebug -Title "Reactivated pool response" -Value $ActivePool
        throw "Traffic Pool was not restored to ACTIVE."
    }

    Write-Host "[OK] ADMIN can pause and reactivate Traffic Pool." -ForegroundColor Green

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "[OK] STAGE 3C RUNTIME VALIDATION PASSED." -ForegroundColor Green
    Write-Host "[OK] Traffic Pool CRUD validated." -ForegroundColor Green
    Write-Host "[OK] Membership eligibility validated." -ForegroundColor Green
    Write-Host "[OK] Deterministic member positions validated." -ForegroundColor Green
    Write-Host "[OK] Member reordering validated." -ForegroundColor Green
    Write-Host "[OK] Membership pause validated." -ForegroundColor Green
    Write-Host "[OK] Removal position compaction validated." -ForegroundColor Green
    Write-Host "[OK] EMPLOYEE read boundary validated." -ForegroundColor Green
    Write-Host "[OK] EMPLOYEE write denial validated." -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
}
finally {
    if (
        $null -ne $Process -and
        -not $Process.HasExited
    ) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    }

    if ($HadPreviousPort) {
        $env:PORT = $PreviousPort
    }
    else {
        Remove-Item Env:PORT -ErrorAction SilentlyContinue
    }

    $AdminPassword = $null
    $EmployeePassword = $null
}