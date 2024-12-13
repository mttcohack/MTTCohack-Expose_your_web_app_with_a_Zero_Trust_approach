$location = "italynorth"
$dnsDomainName = "omegamadlab.it"
$dnsDomainARecordName = "zerotrust04"


New-AzDeployment -TemplateFile .\main.bicep `
    -location $location `
    -dnsDomainName $dnsDomainName `
    -dnsDomainARecordName $dnsDomainARecordName `
    -locationFromTemplate $location


# Upload certificate for the webapp to the Key Vault
$certName = Read-host -Prompt "Please provide the name of your certificate file (ex. zerotrustxx.pfx)"
$certPwd = Read-Host -Prompt "Please provide the password for the certificate" -AsSecureString
$kv = Get-AzKeyVault -ResourceGroupName "COHACK-ZEROTRUSTWEBAPP-RG" | Select-Object -First 1
$kv | Set-AzKeyVaultAccessPolicy -UserPrincipalName (Get-AzContext).Account -PermissionsToCertificates all -PermissionsToSecrets all
Import-AzKeyVaultCertificate -VaultName $kv.VaultName -Name "zerotrust-publicCA" -FilePath ".\$certName" -Password $certPwd

# Create a user assigned Managed Identity to access the KV
$usrMsi = New-AzUserAssignedIdentity -ResourceGroupName "COHACK-ZEROTRUSTWEBAPP-RG" -Name "COHACK-ManagedIdentity" -Location $location
$kv | Set-AzKeyVaultAccessPolicy -ObjectId $usrMsi.PrincipalId -PermissionsToCertificates get -PermissionsToSecrets get -BypassObjectIdValidation

