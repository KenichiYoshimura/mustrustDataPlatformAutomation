// Azure Custom Vision Service (for Circle Detection)
param predictionName string
param trainingName string
param location string
param sku string = 'S0' // S0 = Standard

// Tags
param tags object = {}

// Custom Vision Training Resource
resource customVisionTraining 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: trainingName
  location: location
  tags: tags
  kind: 'CustomVision.Training'
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: trainingName
    publicNetworkAccess: 'Enabled'
  }
}

// Custom Vision Prediction Resource
resource customVisionPrediction 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: predictionName
  location: location
  tags: tags
  kind: 'CustomVision.Prediction'
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: predictionName
    publicNetworkAccess: 'Enabled'
  }
}

// Outputs
output trainingId string = customVisionTraining.id
output trainingName string = customVisionTraining.name
output trainingEndpoint string = customVisionTraining.properties.endpoint

output predictionId string = customVisionPrediction.id
output predictionName string = customVisionPrediction.name
output predictionEndpoint string = customVisionPrediction.properties.endpoint
