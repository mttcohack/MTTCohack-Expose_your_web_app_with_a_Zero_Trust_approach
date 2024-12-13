param location string
param envPrefix string
param dnsDomainName string
param dnsDomainARecordName string

var spokeSubnetList = [
  {
    name: 'wafSubnet'
    subnetPrefix: '192.168.1.0/24'
  }
  {
    name: 'appSubnet'
    subnetPrefix: '192.168.0.0/24'
  }
]

var appPrivateEndpointIp = '192.168.0.10'

// var rtList = [
//   {
//     name: 'WAF-RT'
//     routes: [
//       {
//         name: 'to-app'
//         addressPrefix: first(filter(spokeSubnetList, s => s.name == 'appSubnet')).subnetPrefix
//       }
//     ]
//   }
//   {
//     name: 'APP-RT'
//     routes: [
//       {
//         name: 'to-waf'
//         addressPrefix: first(filter(spokeSubnetList, s => s.name == 'wafSubnet')).subnetPrefix
//       }
//     ]
//   }
// ]

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'HUB-VNET'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/22'
      ]
    }
  }
}

resource fwSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  name: 'AzureFirewallSubnet'
  parent: hubVnet
  properties: {
    addressPrefix: '10.0.0.0/26'
  }
}

resource fwPolicy 'Microsoft.Network/firewallPolicies@2023-09-01' = {
  name: 'AZFW-POLICY'
  location: location
  properties: {
    threatIntelMode: 'Alert'
    sku: {
      tier: 'Premium'
    }
  }
}

resource fwPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'AZFW-PIP'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource fw 'Microsoft.Network/azureFirewalls@2023-09-01' = {
  name: 'AZFW'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Premium'
    }
    ipConfigurations: [
      {
        name: 'AzureFirewallIpConfig'
        properties: {
          subnet: {
            id: fwSubnet.id
          }
          publicIPAddress: {
            id: fwPip.id
          }
        }
      }
    ]
    firewallPolicy: {
      id: fwPolicy.id
    }
  }
}

output fwPublicIP string = fwPip.properties.ipAddress
output fwPrivateIP string = fw.properties.ipConfigurations[0].properties.privateIPAddress

// resource rt 'Microsoft.Network/routeTables@2023-04-01' = [for rt in rtList: {  
//   name: rt.name
//   location: location
//   properties: {
//     routes: [
//       for route in rt.routes: {
//         name: route.name
//         properties: {
//           addressPrefix: route.addressPrefix
//           nextHopType: 'VirtualAppliance'
//           nextHopIpAddress: fw.properties.ipConfigurations[0].properties.privateIPAddress
//         }
//       }
//     ]
//     disableBgpRoutePropagation: true
//   }
// }]

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: 'SPOKE-VNET'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.0.0/23'
      ]
    }
  }
}

resource wafSubnetNsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'wafSubnet-NSG'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAppGwPorts'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '62000-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowHttpsInbound'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '192.168.1.0/24'
        }
      }
    ]
  }
}

resource appSubnetNsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: 'appSubnet-NSG'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAppGw'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '192.168.1.0/24'
          destinationAddressPrefix: '192.168.0.0/24'
        }
      }
    ]
  }
}

@batchSize(1)
resource spokeSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = [for (subnet, i) in spokeSubnetList: {
  name: subnet.name
  parent: spokeVnet
  properties: {
    privateEndpointNetworkPolicies: 'Enabled'
    addressPrefix: subnet.subnetPrefix
    // routeTable:i == 0 ? null : { id: rt[1].id }
    networkSecurityGroup: i == 0 ? { id: wafSubnetNsg.id } : { id: appSubnetNsg.id }
  }
}]

resource peeringH2S 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  name: 'hub-to-spoke-peer'
  parent: hubVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVnet.id
    }
  }
  dependsOn: [
    spokeSubnet[0]
    spokeSubnet[1]
  ]
}

resource peeringS2H 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-04-01' = {
  name: 'spoke-to-hub-peer'
  parent: spokeVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
  }
  dependsOn: [
    fwSubnet
  ]
}

resource wafIp 'Microsoft.Network/publicIPAddresses@2019-11-01' = {
  name: 'WAF-PIP'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'static'
  }
}

output wafPublicIP string = wafIp.properties.ipAddress

resource appServicePlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: 'WEBAPP-ASP'
  location: location
  sku: {
    name: 'S1'
    capacity: 1
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

resource webApp 'Microsoft.Web/sites@2020-12-01' = {
  name: take('${envPrefix}-${guid(resourceGroup().id)}', 20)
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: []
      linuxFxVersion: 'DOCKER|httpd:latest'
    }
    httpsOnly: true
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'WEBAPP-PE'
  location: location
  properties: {
    subnet: {
      id: spokeSubnet[1].id
    }
    ipConfigurations: [
      {
        name: 'WEBAPP-PE-IPConfig'
        properties: {
          privateIPAddress: appPrivateEndpointIp
          groupId: 'sites'
          memberName: 'sites'
        }
      }
    ]
    privateLinkServiceConnections: [
      {
        name: 'WEBAPP-ServiceConnection'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

resource privateDnsZoneHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'hub-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

resource privateDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'spoke-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnet.id
    }
  }
}

resource privateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  name: 'WEBAPP-PE-DNSZoneGroup'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'default'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: take('${envPrefix}-kv-${guid(resourceGroup().id)}', 23)
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    accessPolicies: [
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

resource splitDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: dnsDomainName
  location: 'global'
}

resource splitDnsZoneSpokeLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: splitDnsZone
  name: 'split-spoke-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnet.id
    }
  }
}

resource splitDnsZoneHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: splitDnsZone
  name: 'split-hub-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

resource dnsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: splitDnsZone
  name: dnsDomainARecordName
  properties: {
    aRecords: [
        {
          ipv4Address: appPrivateEndpointIp
        }
    ]
    ttl: 300
  }
}

