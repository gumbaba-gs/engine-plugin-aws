[#ftl]
[#-- Standard inputs --]
[#assign blueprintObject = blueprint?eval]
[#assign credentialsObject = (credentials?eval).Credentials]
[#assign appSettingsObject = appsettings?eval]
[#assign stackOutputsObject = stackOutputs?eval]

[#-- Reference data --]
[#assign regions = blueprintObject.Regions]
[#assign environments = blueprintObject.Environments]
[#assign categories = blueprintObject.Categories]
[#assign routeTables = blueprintObject.RouteTables]
[#assign networkACLs = blueprintObject.NetworkACLs]
[#assign storage = blueprintObject.Storage]
[#assign processors = blueprintObject.Processors]
[#assign ports = blueprintObject.Ports]
[#assign portMappings = blueprintObject.PortMappings]
[#assign powersOf2 = blueprintObject.PowersOf2]

[#-- Region --]
[#if region??]
    [#assign regionId = region]
    [#assign regionObject = regions[regionId]]
    [#assign regionName = regionObject.Name]
[/#if]

[#-- Tenant --]
[#if blueprintObject.Tenant??]
    [#assign tenantObject = blueprintObject.Tenant]
    [#assign tenantId = tenantObject.Id]
    [#assign tenantName = tenantObject.Name]
[/#if]

[#-- Account --]
[#if blueprintObject.Account??]
    [#assign accountObject = blueprintObject.Account]
    [#assign accountId = accountObject.Id]
    [#assign accountName = accountObject.Name]
    [#if accountRegion??]
        [#assign accountRegionId = accountRegion]
        [#assign accountRegionObject = regions[accountRegionId]]
        [#assign accountRegionName = accountRegionObject.Name]
    [/#if]
    [#assign credentialsBucket = getKey("s3","account", "credentials")!"unknown"]
    [#assign codeBucket = getKey("s3","account","code")!"unknown"]
    [#assign registryBucket = getKey("s3", "account", "registry")!"unknown"]
[/#if]

[#-- Product --]
[#if blueprintObject.Product??]
    [#assign productObject = blueprintObject.Product]
    [#assign productId = productObject.Id]
    [#assign productName = productObject.Name]
    [#if productRegion??]
        [#assign productRegionId = productRegion]
        [#assign productRegionObject = regions[productRegionId]]
        [#assign productRegionName = productRegionObject.Name]
    [/#if]
[/#if]

[#-- Segment --]
[#if blueprintObject.Segment??]
    [#assign segmentObject = blueprintObject.Segment]
    [#assign segmentId = segmentObject.Id]
    [#assign segmentName = segmentObject.Name]
    [#assign sshPerSegment = segmentObject.SSHPerSegment]
    [#assign internetAccess = segmentObject.InternetAccess]
    [#assign jumpServer = internetAccess && segmentObject.NAT.Enabled]
    [#assign jumpServerPerAZ = jumpServer && segmentObject.NAT.MultiAZ]
    [#assign operationsBucket = "unknown"]
    [#assign operationsBucketSegment = "segment"]
    [#assign operationsBucketType = "ops"]
    [#if getKey("s3", "segment", "ops")??]
        [#assign operationsBucket = getKey("s3", "segment", "ops")]        
    [/#if]
    [#if getKey("s3", "segment", "operations")??]
        [#assign operationsBucket = getKey("s3", "segment", "operations")]        
    [/#if]
    [#if getKey("s3", "segment", "logs")??]
        [#assign operationsBucket = getKey("s3", "segment", "logs")]        
        [#assign operationsBucketType = "logs"]
    [/#if]
    [#if getKey("s3", "container", "logs")??]
        [#assign operationsBucket = getKey("s3", "container", "logs")]        
        [#assign operationsBucketSegment = "container"]
        [#assign operationsBucketType = "logs"]
    [/#if]
    [#assign dataBucket = "unknown"]
    [#assign dataBucketSegment = "segment"]
    [#assign dataBucketType = "data"]
    [#if getKey("s3", "segment", "data")??]
        [#assign dataBucket = getKey("s3", "segment", "data")]        
    [/#if]
    [#if getKey("s3", "segment", "backups")??]
        [#assign dataBucket = getKey("s3", "segment", "backups")]        
        [#assign dataBucketType = "backups"]
    [/#if]
    [#if getKey("s3", "container", "backups")??]
        [#assign dataBucket = getKey("s3", "container", "backups")]        
        [#assign dataBucketSegment = "container"]
        [#assign dataBucketType = "backups"]
    [/#if]
    [#assign segmentDomain = getKey("domain", "segment", "domain")!"unknown"]
    [#assign segmentDomainQualifier = getKey("domain", "segment", "qualifier")!"unknown"]
    [#assign certificateId = getKey("domain", "segment", "certificate")!"unknown"]
    [#assign vpc = getKey("vpc", "segment", "vpc")!"unknown"]
    [#assign securityGroupNAT = getKey("securityGroup", "mgmt", "nat")!"none"]
    [#if segmentObject.Environment??]
        [#assign environmentId = segmentObject.Environment]
        [#assign environmentObject = environments[environmentId]]
        [#assign environmentName = environmentObject.Name]
        [#assign categoryId = segmentObject.Category!environmentObject.Category]
        [#assign categoryObject = categories[categoryId]]
    [/#if]
[/#if]

[#-- Solution --]
[#if blueprintObject.Solution??]
    [#assign solutionObject = blueprintObject.Solution]
    [#assign solnMultiAZ = solutionObject.MultiAZ!(environmentObject.MultiAZ)!false]
[/#if]

[#-- Concatenate sequence of non-empty strings with a separator --]
[#function concatenate args separator]
    [#local content = []]
    [#list args as arg]
        [#if arg?has_content]
            [#local content += [arg]]
        [/#if]
    [/#list]
    [#return content?join(separator)]
[/#function]

[#-- Format an id - largely used for resource ids which have severe character constraints --]
[#function formatId args...]
    [#return concatenate(args, "X")]
[/#function]

[#-- Format a name - largely used for names that appear in the AWS console --]
[#function formatName args...]
    [#return concatenate(args, "-")]
[/#function]

[#-- Check if deployment unit occurs anywhere in provided object --]
[#function deploymentRequired obj unit]
    [#if obj?is_hash]
        [#if obj.DeploymentUnits?? && obj.DeploymentUnits?seq_contains(unit)]
            [#return true]
        [#else]
            [#list obj?values as attribute]
                [#if deploymentRequired(attribute unit)]
                    [#return true]
                [/#if]
            [/#list]
        [/#if]
    [/#if]
    [#return false]
[/#function]

[#-- Get stack output --]
[#function getKey args...]
    [#-- Line below should be sufficient but triggers bug in jq --]
    [#-- where result of call to concatenate is returned if no match --]
    [#-- on a stack output is found --]
    [#-- TODO: remove copied code when fixed in new version of jq --]
    [#-- local key = concatenate(args, "X") --]
    [#local content = []]
    [#list args as arg]
        [#if arg?has_content]
            [#local content += [arg]]
        [/#if]
    [/#list]
    [#local key = content?join("X")]
    [#list stackOutputsObject as pair]
        [#if pair.OutputKey == key]
            [#return pair.OutputValue]
        [/#if]
    [/#list]
[/#function]

[#-- Get a reference to a resource --]
[#-- Check if resource has already been defined via getKey --]
[#-- If not, assume a reference to a resource in the existing template --]
[#function getReference args...]
    [#local key = concatenate(args, "X")]
    [#if getKey(key)??]
        [#return getKey(key) ]
    [#else]
        [#return { "Ref" : key }]
    [/#if]
[/#function]

[#macro reference value]
    [#if value?is_hash && value.Ref??]
        { "Ref" : "${value.Ref}" }
    [#else]
        "${value}"
    [/#if]
[/#macro]

[#function getTier tierId]
    [#return blueprintObject.Tiers[tierId]]
[/#function]

[#-- Locate the object for a component within tier --]
[#function getComponent tierId componentId]
    [#local tier = getTier(tierId)]
    [#list tier.Components?values as component]
        [#if componentId == component.Id]
            [#return component]
        [/#if]
    [/#list]
[/#function]

[#-- Calculate the closest power of 2 --]
[#function getPowerOf2 value]
    [#local exponent = -1]
    [#list powersOf2 as powerOf2]
        [#if powerOf2 <= value]
            [#local exponent = powerOf2?index]
        [#else]
            [#break]
        [/#if]
    [/#list]
    [#return exponent]
[/#function]

[#-- Required tiers --]
[#function isTier tierId]
    [#return (blueprintObject.Tiers[tierId])??]
[/#function]

[#assign tiers = []]
[#list segmentObject.Tiers.Order as tierId]
    [#if isTier(tierId)]
        [#assign tier = getTier(tierId)]
        [#if tier.Components??
            || ((tier.Required)?? && tier.Required)
            || (jumpServer && (tierId == "mgmt"))]
            [#assign tiers += [tier + 
                {"Index" : tierId?index}]]
        [/#if]
    [/#if]
[/#list]

[#-- Required zones --]
[#assign zones = []]
[#list segmentObject.Zones.Order as zoneId]
    [#if regions[region].Zones[zoneId]??]
        [#assign zone = regions[region].Zones[zoneId]]
        [#assign zones += [zone +  
            {"Index" : zoneId?index}]]
    [/#if]
[/#list]

[#-- Get processor settings --]
[#function getProcessor tier component type]
    [#local tc = tier.Id + "-" + component.Id]
    [#local defaultProfile = "default"]
    [#if (component[type].Processor)??]
        [#return component[type].Processor]
    [/#if]
    [#if (processors[solutionObject.CapacityProfile][tc])??]
        [#return processors[solutionObject.CapacityProfile][tc]]
    [/#if]
    [#if (processors[solutionObject.CapacityProfile][type])??]
        [#return processors[solutionObject.CapacityProfile][type]]
    [/#if]
    [#if (processors[defaultProfile][tc])??]
        [#return processors[defaultProfile][tc]]
    [/#if]
    [#if (processors[defaultProfile][type])??]
        [#return processors[defaultProfile][type]]
    [/#if]
[/#function]


[#-- Get storage settings --]
[#function getStorage tier component type]
    [#local tc = tier.Id + "-" + component.Id]
    [#local defaultProfile = "default"]
    [#if (component[type].Storage)??]
        [#return component[type].Storage]
    [/#if]
    [#if (storage[solutionObject.CapacityProfile][tc])??]
        [#return storage[solutionObject.CapacityProfile][tc]]
    [/#if]
    [#if (storage[solutionObject.CapacityProfile][type])??]
        [#return storage[solutionObject.CapacityProfile][type]]
    [/#if]
    [#if (storage[defaultProfile][tc])??]
        [#return storage[defaultProfile][tc]]
    [/#if]
    [#if (storage[defaultProfile][type])??]
        [#return storage[defaultProfile][type]]
    [/#if]
[/#function]

[#macro securityGroup mode tier component idStem="" nameStem=""]
    [#if resourceCount > 0],[/#if]
    [#switch mode]
        [#case "definition"]
            "${formatId("securityGroup", componentIdStem, idStem)}" : {
                "Type" : "AWS::EC2::SecurityGroup",
                "Properties" : {
                    "GroupDescription": "Security Group for ${formatName(componentNameStem, nameStem)}",
                    "VpcId": "${vpc}",
                    "Tags" : [
                        { "Key" : "cot:request", "Value" : "${requestReference}" },
                        { "Key" : "cot:configuration", "Value" : "${configurationReference}" },
                        { "Key" : "cot:tenant", "Value" : "${tenantId}" },
                        { "Key" : "cot:account", "Value" : "${accountId}" },
                        { "Key" : "cot:product", "Value" : "${productId}" },
                        { "Key" : "cot:segment", "Value" : "${segmentId}" },
                        { "Key" : "cot:environment", "Value" : "${environmentId}" },
                        { "Key" : "cot:category", "Value" : "${categoryId}" },
                        { "Key" : "cot:tier", "Value" : "${tier.Id}" },
                        { "Key" : "cot:component", "Value" : "${component.Id}" },
                        { "Key" : "Name", "Value" : "${formatName(componentNameStem, nameStem)}" }
                    ]
                }
            }
            [#break]

        [#case "outputs"]
            "${formatId("securityGroup", componentIdStem, idStem)}" : {
                "Value" : { "Ref" : "${formatId("securityGroup", componentIdStem, idStem)}" }
            }
            [#break]

    [/#switch]
    [#assign resourceCount += 1]
[/#macro]
