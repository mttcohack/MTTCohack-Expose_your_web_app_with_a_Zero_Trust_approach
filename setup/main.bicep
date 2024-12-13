targetScope = 'subscription'

param location string
param dnsDomainName string
param dnsDomainARecordName string

resource rgZeroTrust 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'COHACK-ZEROTRUSTWEBAPP-RG'
  location: location
}

module zeroTrustEnvironment 'challenges.bicep' = {
  name: 'zero-trust-environment'
  scope: rgZeroTrust
  params: {
    location: location
    envPrefix: 'COHACK'
    dnsDomainName: dnsDomainName
    dnsDomainARecordName: dnsDomainARecordName
  }
}

output wafPublicIp string = zeroTrustEnvironment.outputs.wafPublicIP
output fwPrivateIp string = zeroTrustEnvironment.outputs.fwPrivateIP
