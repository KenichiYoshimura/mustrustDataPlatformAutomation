// Cosmos DB Account and Containers for Silver & Gold Layers
param cosmosAccountName string
param location string
param databaseName string = 'mustrustDataPlatform'

// Container names
param silverContainerName string = 'silver-extracted-documents'
param goldContainerName string = 'gold-enriched-documents'
param leasesContainerName string = 'leases'

// Throughput settings
param silverMaxThroughput int = 4000
param goldMaxThroughput int = 4000
param leasesMinThroughput int = 400

// Tags
param tags object = {}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    capabilities: []
  }
}

// Database
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// Silver Container: silver-extracted-documents
resource silverContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: database
  name: silverContainerName
  properties: {
    resource: {
      id: silverContainerName
      partitionKey: {
        paths: [
          '/documentType'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
    options: {
      autoscaleSettings: {
        maxThroughput: silverMaxThroughput
      }
    }
  }
}

// Gold Container: gold-enriched-documents
resource goldContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: database
  name: goldContainerName
  properties: {
    resource: {
      id: goldContainerName
      partitionKey: {
        paths: [
          '/documentType'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/extractedData/*'
          }
          {
            path: '/enrichment/translation/translatedFields/*'
          }
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
    options: {
      autoscaleSettings: {
        maxThroughput: goldMaxThroughput
      }
    }
  }
}

// Leases Container: leases (for Change Feed)
resource leasesContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: database
  name: leasesContainerName
  properties: {
    resource: {
      id: leasesContainerName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
    options: {
      throughput: leasesMinThroughput
    }
  }
}

// Outputs
output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output databaseName string = database.name
output silverContainerName string = silverContainer.name
output goldContainerName string = goldContainer.name
output leasesContainerName string = leasesContainer.name
