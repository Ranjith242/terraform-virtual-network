$SubscriptionId = "----"
$TagName        = "CostCenter"
$Location       = "eastus"   # required when MSI is attached
$ResourceGroups = @("rg-finops-prod", "rg-finops-nonprod")

Connect-AzAccount -ErrorAction SilentlyContinue | Out-Null
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$policyDef = Get-AzPolicyDefinition -Id `
   "/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcdc54f7b070"

foreach ($rg in $ResourceGroups) {
    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$rg"

    New-AzPolicyAssignment `
        -Name             "inherit-$($TagName.ToLower())-$rg" `
        -DisplayName      "Inherit '$TagName' tag from RG ($rg)" `
        -PolicyDefinition $policyDef `
        -Scope            $scope `
        -IdentityType     SystemAssigned `
        -Location         $Location `
        -PolicyParameterObject @{ tagName = $TagName }

    Write-Host "Assigned to $rg" -ForegroundColor Green
}
