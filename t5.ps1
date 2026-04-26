<#
.SYNOPSIS
    Finds unattached Azure managed disks within a given scope (Subscription or 
    ResourceGroup), optionally filters by the "Environment" tag, lists them, 
    and prompts for approval before deletion.

.DESCRIPTION
    Scope can be:
      - Subscription : scans all managed disks in the given subscription
      - ResourceGroup: scans only disks in the specified resource group
    Filters disks with DiskState='Unattached' or empty ManagedBy.
    Optionally filters by tag "Environment" = <value>.
    Lists matching disks and asks for confirmation before deletion.

.PARAMETER SubscriptionId
    The Azure Subscription ID. Required for both scopes.

.PARAMETER Scope
    Either 'Subscription' or 'ResourceGroup'. Default is 'Subscription'.

.PARAMETER ResourceGroupName
    Required when -Scope is 'ResourceGroup'.

.PARAMETER EnvironmentTagValue
    Optional. Only include disks where tag "Environment" equals this value.

.PARAMETER Force
    Optional. Skip the confirmation prompt.

.EXAMPLE
    # Subscription-wide
    .\Remove-UnattachedManagedDisks.ps1 -SubscriptionId "xxxx" -Scope Subscription

.EXAMPLE
    # Resource group scope
    .\Remove-UnattachedManagedDisks.ps1 -SubscriptionId "xxxx" -Scope ResourceGroup -ResourceGroupName "rg-prod"

.EXAMPLE
    # Subscription-wide with Environment tag filter
    .\Remove-UnattachedManagedDisks.ps1 -SubscriptionId "xxxx" -EnvironmentTagValue "Dev"

.EXAMPLE
    # Resource group with tag filter, no prompt
    .\Remove-UnattachedManagedDisks.ps1 -SubscriptionId "xxxx" -Scope ResourceGroup -ResourceGroupName "rg-dev" -EnvironmentTagValue "Dev" -Force
#>

[CmdletBinding(DefaultParameterSetName = 'Subscription')]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Subscription', 'ResourceGroup')]
    [string]$Scope = 'Subscription',

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentTagValue,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# ---- Validate scope/parameter combination ----
if ($Scope -eq 'ResourceGroup' -and [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    Write-Error "When -Scope is 'ResourceGroup', -ResourceGroupName is required."
    return
}

# ---- Ensure Az modules are available ----
if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-Error "The Az.Compute module is required. Install it with: Install-Module -Name Az -Scope CurrentUser"
    return
}

Import-Module Az.Accounts -ErrorAction SilentlyContinue
Import-Module Az.Compute  -ErrorAction SilentlyContinue

# ---- Ensure user is signed in ----
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "No Azure context found. Initiating login..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
}

# ---- Set subscription context ----
try {
    Write-Host "Setting context to subscription: $SubscriptionId" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Failed to set subscription context: $_"
    return
}

# ---- Retrieve managed disks based on scope ----
Write-Host "Retrieving managed disks (Scope: $Scope)..." -ForegroundColor Cyan
try {
    switch ($Scope) {
        'ResourceGroup' {
            $allDisks = Get-AzDisk -ResourceGroupName $ResourceGroupName -ErrorAction Stop
            $scopeDescription = "resource group '$ResourceGroupName' in subscription '$SubscriptionId'"
        }
        'Subscription' {
            $allDisks = Get-AzDisk -ErrorAction Stop
            $scopeDescription = "subscription '$SubscriptionId'"
        }
    }
}
catch {
    Write-Error "Failed to retrieve disks: $_"
    return
}

Write-Host "Found $($allDisks.Count) total managed disk(s) in $scopeDescription." -ForegroundColor Green

# ---- Filter unattached disks ----
$unattachedDisks = $allDisks | Where-Object {
    $_.DiskState -eq 'Unattached' -or [string]::IsNullOrEmpty($_.ManagedBy)
}

Write-Host "Found $($unattachedDisks.Count) unattached disk(s)." -ForegroundColor Green

# ---- Optional Environment tag filter ----
if ($PSBoundParameters.ContainsKey('EnvironmentTagValue') -and $EnvironmentTagValue) {
    Write-Host "Filtering by tag Environment = '$EnvironmentTagValue'..." -ForegroundColor Cyan
    $unattachedDisks = $unattachedDisks | Where-Object {
        $_.Tags -and
        $_.Tags.ContainsKey('Environment') -and
        $_.Tags['Environment'] -eq $EnvironmentTagValue
    }
    Write-Host "After tag filter: $($unattachedDisks.Count) disk(s) remain." -ForegroundColor Green
}

# ---- Exit if nothing to delete ----
if (-not $unattachedDisks -or $unattachedDisks.Count -eq 0) {
    Write-Host "No matching unattached managed disks found. Nothing to do." -ForegroundColor Yellow
    return
}

# ---- Display the list ----
Write-Host ""
Write-Host "==================== Unattached Managed Disks ====================" -ForegroundColor Magenta
$unattachedDisks |
    Select-Object @{N='Name';E={$_.Name}},
                  @{N='ResourceGroup';E={$_.ResourceGroupName}},
                  @{N='Location';E={$_.Location}},
                  @{N='SizeGB';E={$_.DiskSizeGB}},
                  @{N='Sku';E={$_.Sku.Name}},
                  @{N='DiskState';E={$_.DiskState}},
                  @{N='Environment';E={ if ($_.Tags) { $_.Tags['Environment'] } else { '' } }} |
    Format-Table -AutoSize

Write-Host "Total disks targeted for deletion: $($unattachedDisks.Count)" -ForegroundColor Yellow
Write-Host ""

# ---- Approval prompt ----
$proceed = $false
if ($Force) {
    $proceed = $true
    Write-Host "-Force specified. Skipping confirmation." -ForegroundColor Yellow
}
else {
    $response = Read-Host "Do you want to DELETE the disks listed above? Type 'YES' to confirm"
    if ($response -ceq 'YES') {
        $proceed = $true
    }
    else {
        Write-Host "Deletion cancelled by user." -ForegroundColor Yellow
        return
    }
}

# ---- Perform deletion ----
if ($proceed) {
    $deleted = 0
    $failed  = 0
    foreach ($disk in $unattachedDisks) {
        try {
            Write-Host "Deleting disk '$($disk.Name)' in RG '$($disk.ResourceGroupName)'..." -ForegroundColor Cyan
            Remove-AzDisk -ResourceGroupName $disk.ResourceGroupName -DiskName $disk.Name -Force -ErrorAction Stop | Out-Null
            Write-Host "  Deleted: $($disk.Name)" -ForegroundColor Green
            $deleted++
        }
        catch {
            Write-Warning "  Failed to delete '$($disk.Name)': $_"
            $failed++
        }
    }

    Write-Host ""
    Write-Host "==================== Summary ====================" -ForegroundColor Magenta
    Write-Host "Successfully deleted: $deleted" -ForegroundColor Green
    Write-Host "Failed:               $failed" -ForegroundColor Red
}
