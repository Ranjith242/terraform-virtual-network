<#
.SYNOPSIS
    One-time deployment of a FinOps lab environment in Azure.
    Resource Group names are supplied by the user; all other names are derived from them.

.PARAMETER Location
    Azure region (e.g. eastus, westeurope, centralindia).

.PARAMETER SubscriptionId
    Target subscription.

.PARAMETER ProdResourceGroupName
    Name of the PROD resource group (e.g. rg-finops-prod).

.PARAMETER NonProdResourceGroupName
    Name of the NON-PROD resource group (e.g. rg-finops-nonprod).

.PARAMETER AdminUsername / AdminPassword
    Local admin credentials for the VMs.

.PARAMETER DeployLoadBalancer
    Switch to also deploy the optional internal load balancers.

.EXAMPLE
    $pwd = ConvertTo-SecureString "P@ssw0rd1234!" -AsPlainText -Force
    .\Deploy-FinOpsLab.ps1 `
        -SubscriptionId           "<sub-id>" `
        -Location                 "eastus" `
        -ProdResourceGroupName    "rg-finops-prod" `
        -NonProdResourceGroupName "rg-finops-nonprod" `
        -AdminUsername "azureuser" -AdminPassword $pwd `
        -DeployLoadBalancer
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Location,
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ProdResourceGroupName,
    [Parameter(Mandatory)] [string] $NonProdResourceGroupName,
    [Parameter(Mandatory)] [string] $AdminUsername,
    [Parameter(Mandatory)] [SecureString] $AdminPassword,
    [switch] $DeployLoadBalancer
)

$ErrorActionPreference = 'Stop'

# ---------- Connect ----------
if (-not (Get-AzContext)) { Connect-AzAccount | Out-Null }
Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null

# ---------- Helpers ----------
function Get-EnvSuffix {
    param([string]$RgName)
    $s = $RgName.ToLower()
    if ($s.StartsWith('rg-')) { $s = $s.Substring(3) }   # rg-finops-prod -> finops-prod
    return $s
}

function Get-AlphaNum {
    param([string]$Value)
    return ($Value.ToLower() -replace '[^a-z0-9]', '')
}

# ---------- Definition table (derived from user-supplied RG names) ----------
$envs = @(
    @{
        Tag          = 'prod'
        Rg           = $ProdResourceGroupName
        Suffix       = Get-EnvSuffix $ProdResourceGroupName
        Vnet         = "vnet-$(Get-EnvSuffix $ProdResourceGroupName)"
        VnetCidr     = '10.10.0.0/16'
        VmSubnetCidr = '10.10.1.0/24'
        LbSubnetCidr = '10.10.2.0/24'
    },
    @{
        Tag          = 'nonprod'
        Rg           = $NonProdResourceGroupName
        Suffix       = Get-EnvSuffix $NonProdResourceGroupName
        Vnet         = "vnet-$(Get-EnvSuffix $NonProdResourceGroupName)"
        VnetCidr     = '10.20.0.0/16'
        VmSubnetCidr = '10.20.1.0/24'
        LbSubnetCidr = '10.20.2.0/24'
    }
)

# Random suffix for globally-unique names (storage)
$rand = -join ((97..122) + (48..57) | Get-Random -Count 5 | ForEach-Object {[char]$_})

$cred = New-Object System.Management.Automation.PSCredential ($AdminUsername, $AdminPassword)

function New-LabVM {
    param(
        [string]$Rg, [string]$Location, [string]$VmName,
        [string]$SubnetId, [ValidateSet('Windows','Linux')] [string]$OsType,
        [pscredential]$Cred, [string]$Size = 'Standard_B2s'
    )

    $nicName = "$VmName-nic"
    $nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $Rg -Location $Location -SubnetId $SubnetId -Force

    $vmConfig = New-AzVMConfig -VMName $VmName -VMSize $Size

    if ($OsType -eq 'Windows') {
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName ($VmName.Substring(0,[Math]::Min(15,$VmName.Length))) -Credential $Cred -ProvisionVMAgent -EnableAutoUpdate
        $vmConfig = Set-AzVMSourceImage  -VM $vmConfig -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2022-Datacenter' -Version 'latest'
    } else {
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux   -ComputerName $VmName -Credential $Cred
        $vmConfig = Set-AzVMSourceImage    -VM $vmConfig -PublisherName 'Canonical' -Offer '0001-com-ubuntu-server-jammy' -Skus '22_04-lts-gen2' -Version 'latest'
    }

    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
    $vmConfig = Set-AzVMBootDiagnostic   -VM $vmConfig -Disable

    Write-Host "  Creating VM $VmName ($OsType) ..." -ForegroundColor Cyan
    New-AzVM -ResourceGroupName $Rg -Location $Location -VM $vmConfig | Out-Null
}

foreach ($e in $envs) {

    $tag      = $e.Tag
    $suffix   = $e.Suffix
    $rg       = $e.Rg
    $vnetName = $e.Vnet

    Write-Host "`n=== Deploying [$tag] -> RG '$rg' in '$Location' ===" -ForegroundColor Yellow

    # ---------- Resource Group ----------
    if (-not (Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue)) {
        New-AzResourceGroup -Name $rg -Location $Location | Out-Null
    }

    # ---------- VNet + Subnets ----------
    $vmSubnet = New-AzVirtualNetworkSubnetConfig -Name 'Vmsubnet' -AddressPrefix $e.VmSubnetCidr
    $lbSubnet = New-AzVirtualNetworkSubnetConfig -Name 'Lbsubnet' -AddressPrefix $e.LbSubnetCidr
    $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $rg -Location $Location `
            -AddressPrefix $e.VnetCidr -Subnet $vmSubnet,$lbSubnet -Force

    $vmSubnetId = ($vnet.Subnets | Where-Object Name -eq 'Vmsubnet').Id
    $lbSubnetId = ($vnet.Subnets | Where-Object Name -eq 'Lbsubnet').Id

    # ---------- Storage account ----------
    $saBase = "sa$(Get-AlphaNum $suffix)$rand"
    $saName = $saBase.Substring(0, [Math]::Min(24, $saBase.Length))
    Write-Host "  Creating Storage Account $saName ..." -ForegroundColor Cyan
    New-AzStorageAccount -ResourceGroupName $rg -Name $saName -Location $Location `
        -SkuName Standard_LRS -Kind StorageV2 -MinimumTlsVersion TLS1_2 | Out-Null

    # ---------- Public IP ----------
    $pipName = "pip-$suffix"
    Write-Host "  Creating Public IP $pipName ..." -ForegroundColor Cyan
    New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rg -Location $Location `
        -AllocationMethod Static -Sku Standard | Out-Null

    # ---------- Unattached Managed Disk ----------
    $diskName   = "disk-$suffix-unattached"
    $diskConfig = New-AzDiskConfig -Location $Location -CreateOption Empty -DiskSizeGB 32 -SkuName Standard_LRS
    Write-Host "  Creating Unattached Managed Disk $diskName ..." -ForegroundColor Cyan
    New-AzDisk -ResourceGroupName $rg -DiskName $diskName -Disk $diskConfig | Out-Null

    # ---------- VMs ----------
    if ($tag -eq 'prod') {
        New-LabVM -Rg $rg -Location $Location -VmName "vm-win-$tag" -SubnetId $vmSubnetId -OsType Windows -Cred $cred
        New-LabVM -Rg $rg -Location $Location -VmName "vm-lnx-$tag" -SubnetId $vmSubnetId -OsType Linux   -Cred $cred
    }

    # Dev VM in BOTH environments
    New-LabVM -Rg $rg -Location $Location -VmName "vm-dev-$tag" -SubnetId $vmSubnetId -OsType Linux -Cred $cred

    # ---------- Optional Internal Load Balancer ----------
    if ($DeployLoadBalancer) {
        $lbName     = "lb-$suffix"
        $feIpName   = "$lbName-fe"
        $bePoolName = "$lbName-bepool"
        $probeName  = "$lbName-probe"
        $ruleName   = "$lbName-rule"

        Write-Host "  Creating Internal Load Balancer $lbName ..." -ForegroundColor Cyan
        $feIp   = New-AzLoadBalancerFrontendIpConfig -Name $feIpName -SubnetId $lbSubnetId -PrivateIpAddressVersion IPv4
        $bePool = New-AzLoadBalancerBackendAddressPoolConfig -Name $bePoolName
        $probe  = New-AzLoadBalancerProbeConfig -Name $probeName -Protocol Tcp -Port 80 -IntervalInSeconds 15 -ProbeCount 2
        $rule   = New-AzLoadBalancerRuleConfig -Name $ruleName -Protocol Tcp `
                     -FrontendPort 80 -BackendPort 80 `
                     -FrontendIpConfiguration $feIp -BackendAddressPool $bePool -Probe $probe

        New-AzLoadBalancer -ResourceGroupName $rg -Name $lbName -Location $Location -Sku Standard `
            -FrontendIpConfiguration $feIp -BackendAddressPool $bePool `
            -Probe $probe -LoadBalancingRule $rule | Out-Null
    }

    Write-Host "=== Completed [$tag] -> $rg ===" -ForegroundColor Green
}

Write-Host "`nAll resources deployed successfully in region '$Location'." -ForegroundColor Green
