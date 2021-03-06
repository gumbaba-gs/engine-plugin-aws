[#ftl]

[#assign ECS_SERVICE_OUTPUT_MAPPINGS =
    {
        REFERENCE_ATTRIBUTE_TYPE : {
            "UseRef" : true
        },
        ARN_ATTRIBUTE_TYPE : {
            "UseRef" : true
        },
        NAME_ATTRIBUTE_TYPE : {
            "Attribute" : "Name"
        },
        REGION_ATTRIBUTE_TYPE: {
            "Value" : { "Ref" : "AWS::Region" }
        }
    }
]

[#assign ECS_TASK_OUTPUT_MAPPINGS =
    {
        REFERENCE_ATTRIBUTE_TYPE : {
            "UseRef" : true
        },
        ARN_ATTRIBUTE_TYPE : {
            "UseRef" : true
        },
        REGION_ATTRIBUTE_TYPE: {
            "Value" : { "Ref" : "AWS::Region" }
        }
    }
]

[#assign ECS_OUTPUT_MAPPINGS =
    {
        REFERENCE_ATTRIBUTE_TYPE : {
            "UseRef" : true
        },
        ARN_ATTRIBUTE_TYPE : {
            "Attribute" : "Arn"
        }
    }]

[#assign ECS_CAPACITYPROVIDER_OUTPUT_MAPPINGS =
    {
        REFERENCE_ATTRIBUTE_TYPE : {
            "UseRef" : true
        }
    }
]

[#assign ecsMappings =
    {
        AWS_ECS_RESOURCE_TYPE : ECS_OUTPUT_MAPPINGS,
        AWS_ECS_SERVICE_RESOURCE_TYPE : ECS_SERVICE_OUTPUT_MAPPINGS,
        AWS_ECS_TASK_RESOURCE_TYPE : ECS_TASK_OUTPUT_MAPPINGS,
        AWS_ECS_CAPACIITY_PROVIDER_RESOURCE_TYPE : ECS_CAPACITYPROVIDER_OUTPUT_MAPPINGS
    }
]

[#list ecsMappings as type, mappings]
    [@addOutputMapping
        provider=AWS_PROVIDER
        resourceType=type
        mappings=mappings
    /]
[/#list]

[#assign metricAttributes +=
    {
        AWS_ECS_RESOURCE_TYPE : {
            "Namespace" : "AWS/ECS",
            "Dimensions" : {
                "ClusterName" : {
                    "Output" : REFERENCE_ATTRIBUTE_TYPE
                }
            }
        },
        AWS_ECS_SERVICE_RESOURCE_TYPE : {
            "Namespace" : "AWS/ECS",
            "Dimensions" : {
                "ClusterName" : {
                    "OtherOutput" : {
                        "Id" : "cluster",
                        "Property" : ""
                    }
                },
                "ServiceName" : {
                    "Output" : NAME_ATTRIBUTE_TYPE
                }
            }
        }
    }
]

[#function getCapacityProviderStrategy capacityProvider weight base="" ]
    [#return
        {
            "CapacityProvider" : capacityProvider,
            "Weight" : weight
        } +
        attributeIfContent(
            "Base",
            base
        )
    ]
[/#function]

[#function getECSCapacityProviderStrategy computeProfileRule asgCapacityProviderId ]
    [#local provider = "" ]
    [#switch computeProfileRule.Provider ]
        [#case "_autoscalegroup" ]
            [#local provider = getReference(asgCapacityProviderId)]
            [#break]
        [#case "aws:fargate" ]
            [#local provider = "FARGATE" ]
            [#break]
        [#case "aws:fargatespot" ]
            [#local provider = "FARGATE_SPOT" ]
            [#break]
    [/#switch]

    [#return
        {
            "CapacityProvider" : provider,
            "Weight" : computeProfileRule.Weight
        } +
        attributeIfContent(
            "Base",
            computeProfileRule.RequiredCount!""
        )
    ]
[/#function]

[#macro createECSCluster
            id
            name=""
            capacityProviders=[]
            defaultCapacityProviderStrategies=[]
            tags={}
            dependencies=[] ]
        [@cfResource
            id=id
            type="AWS::ECS::Cluster"
            outputs=ECS_OUTPUT_MAPPINGS
            tags=tags
            dependencies=dependencies
            properties={
            } +
            attributeIfContent(
                "CapacityProviders",
                capacityProviders
            ) +
            attributeIfContent(
                "DefaultCapacityProviderStrategy",
                defaultCapacityProviderStrategies
            ) +
            attributeIfContent(
                "ClusterName",
                name
            )
        /]
[/#macro]

[#macro createECSTask id
    name
    containers
    engine
    executionRole
    networkMode=""
    fixedName=false
    role=""
    dependencies=""]

    [#local definitions = [] ]
    [#local volumes = []]
    [#local volumeNames = [] ]

    [#local memoryTotal = 0]
    [#local cpuTotal = 0]

    [#local placementConstraints = []]

    [#list containers as container]
        [#local mountPoints = [] ]
        [#list (container.Volumes!{}) as name,volume]
            [#local mountPoints +=
                [
                    {
                        "ContainerPath" : volume.ContainerPath,
                        "SourceVolume" : name,
                        "ReadOnly" : volume.ReadOnly
                    }
                ]
            ]

            [#if ! volumeNames?seq_contains(name) ]
                [#local dockerVolumeConfiguration = {}]
                [#local efsVolumeConfiguration = {}]

                [#switch volume.Driver ]
                    [#case "efs" ]
                        [#local efsVolumeConfiguration +=
                            {
                                "FilesystemId" : volume.EFS.FileSystemId,
                                "TransitEncryption" : "ENABLED",
                                "AuthorizationConfig" : {
                                    "IAM" : "ENABLED"
                                } +
                                attributeIfContent(
                                    "AccessPointId",
                                    (volume.EFS.AccessPointId)!""
                                )
                            }
                        ]
                        [#break]
                    [#default]

                        [#local dockerVolumeConfiguration +=
                            volume.PersistVolume?then(
                                {
                                    "Scope" : "shared",
                                    "Autoprovision", volume.AutoProvision
                                },
                                {}
                            ) +
                            attributeIfContent(
                                "DriverOpts",
                                volume.DriverOpts!{}
                            ) +
                            attributeIfTrue(
                                "Driver",
                                (volume.Driver != "local"),
                                volume.Driver
                            ) +
                            attributeIfContent(
                                "Scope",
                                volume.Scope!""
                            )
                        ]
                [/#switch]


                [#local volumes +=
                    [
                        {
                            "Name" : name
                        } +
                        attributeIfContent(
                            "Host",
                            volume.HostPath,
                            {"SourcePath" : volume.HostPath!""}
                        ) +
                        attributeIfContent(
                            "DockerVolumeConfiguration",
                            dockerVolumeConfiguration
                        ) +
                        attributeIfContent(
                            "EFSVolumeConfiguration",
                            efsVolumeConfiguration
                        )
                    ]
                ]
            [/#if]
            [#local volumeNames += [ name ] ]
        [/#list]
        [#local portMappings = [] ]
        [#list (container.PortMappings![]) as portMapping]
            [#local portMappings +=
                [
                    {
                        "ContainerPort" : ports[portMapping.ContainerPort].Port,
                        "HostPort" : portMapping.DynamicHostPort?then(0, ports[portMapping.HostPort].Port)
                    } +
                    attributeIfTrue(
                        "Protocol",
                        (ports[portMapping.ContainerPort].IPProtocol == "udp"),
                        "udp"
                    )
                ]
            ]
        [/#list]
        [#local environment = [] ]
        [#list (container.Environment!{}) as name,value]
            [#local environment +=
                [
                    {
                        "Name" : name,
                        "Value" : value
                    }
                ]
            ]
        [/#list]
        [#local extraHosts = [] ]
        [#list (container.Hosts!{}) as name,value]
            [#local extraHosts +=
                [
                    {
                        "Hostname" : name,
                        "IpAddress" : value
                    }
                ]
            ]
        [/#list]
        [#local ulimits = []]
        [#list (container.Ulimits!{}) as id, limit ]
            [#local ulimits +=
                [
                    {
                        "Name" : limit.Name,
                        "HardLimit" : limit.HardLimit,
                        "SoftLimit" : limit.SoftLimit
                    }
                ]
            ]
        [/#list]

        [#local placementConstraints = combineEntities( placementConstraints, container.PlacementConstraints![], UNIQUE_COMBINE_BEHAVIOUR) ]

        [#if engine == "fargate" ]
            [#local memoryTotal += container.MaximumMemory]
            [#local cpuTotal += container.Cpu]
        [/#if]
        [#local definitions +=
            [
                {
                    "Name" : container.Name,
                    "Image" :
                        formatRelativePath(
                            container.RegistryEndPoint,
                            container.Image +
                                container.ImageVersion?has_content?then(
                                    ":" + container.ImageVersion,
                                    ""
                                )
                            ),
                    "Essential" : container.Essential,
                    "MemoryReservation" : container.MemoryReservation,
                    "LogConfiguration" :
                        {
                            "LogDriver" : container.LogDriver
                        } +
                        attributeIfContent("Options", container.LogOptions)
                } +
                attributeIfContent("Environment", environment) +
                attributeIfContent("MountPoints", mountPoints) +
                attributeIfContent("ExtraHosts", extraHosts) +
                attributeIfContent("Memory", container.MaximumMemory!"") +
                attributeIfContent("Cpu", container.Cpu!"") +
                attributeIfContent("PortMappings", portMappings) +
                attributeIfContent("LinuxParameters", container.RunCapabilities![],
                                        {
                                            "Capabilities" : {
                                                "Add" : container.RunCapabilities![]
                                            }
                                        }
                                    ) +
                attributeIfTrue("Privileged", container.Privileged, container.Privileged!"") +
                attributeIfContent("WorkingDirectory", container.WorkingDirectory!"") +
                attributeIfContent("Links", container.ContainerNetworkLinks![] ) +
                attributeIfContent("EntryPoint", container.EntryPoint![]) +
                attributeIfContent("Command", container.Command![]) +
                attributeIfContent("HealthCheck", container.HealthCheck!{}) +
                attributeIfContent("Hostname", container.Hostname!"") +
                attributeIfContent("Ulimits", ulimits )
            ]
        ]
    [/#list]

    [#local placementConstraintProps = []]
    [#list placementConstraints as placementConstraint ]
        [#local placementConstraintProps +=
                [
                    {
                        "Type" : "memberOf",
                        "Expression" : placementConstraint
                    }
                ]]
    [/#list]

    [#local taskProperties = {
        "ContainerDefinitions" : definitions
        } +
        attributeIfContent("Volumes", volumes)  +
        attributeIfContent("TaskRoleArn", role, getReference(role, ARN_ATTRIBUTE_TYPE)) +
        attributeIfContent("NetworkMode", networkMode) +
        attributeIfTrue("Family", fixedName, name ) +
        attributeIfContent("ExecutionRoleArn", executionRole, getReference(executionRole, ARN_ATTRIBUTE_TYPE)) +
        valueIfTrue(
            {
                "RequiresCompatibilities" : [ engine?upper_case ],
                "Cpu" : cpuTotal,
                "Memory" : memoryTotal
            },
            (engine == "fargate")
        ) +
        attributeIfContent("PlacementConstraints", placementConstraintProps)
    ]

    [@cfResource
        id=id
        type="AWS::ECS::TaskDefinition"
        properties=taskProperties
        dependencies=dependencies
        outputs=ECS_TASK_OUTPUT_MAPPINGS
    /]
[/#macro]

[#macro createECSService id
            ecsId
            desiredCount
            taskId
            loadBalancers
            serviceRegistries
            engine
            platformVersion=""
            networkMode=""
            networkConfiguration={}
            placement={}
            dependencies=""
    ]

    [#-- define an array of constraints --]
    [#-- for potential support of "memberOf" type placement constraint --]
    [#local placementConstraints = [] ]
    [#if placement.DistinctInstance && (engine != "fargate")]
        [#local placementConstraints += [{
            "Type" : "distinctInstance"
        }]]
    [/#if]

    [@cfResource
        id=id
        type="AWS::ECS::Service"
        properties=
            {
                "Cluster" : getExistingReference(ecsId),
                "TaskDefinition" : getReference(taskId),
                "DeploymentConfiguration" :
                    (desiredCount > 1)?then(
                        {
                            "MaximumPercent" : 100,
                            "MinimumHealthyPercent" : 50
                        },
                        {
                            "MaximumPercent" : 100,
                            "MinimumHealthyPercent" : 0
                        })
            } +
            valueIfContent(
                {
                    "LoadBalancers" : loadBalancers
                },
                loadBalancers) +
            valueIfContent(
                {
                    "ServiceRegistries" : serviceRegistries
                },
                serviceRegistries) +
            valueIfTrue(
                {
                    "SchedulingStrategy" : "DAEMON"
                },
                (placement.Strategy == "daemon" && engine == "ec2" ),
                {
                    "DesiredCount" : desiredCount
                }
            ) +
            attributeIfTrue(
                "LaunchType",
                engine == "fargate",
                engine?upper_case
            ) +
            attributeIfTrue(
                "PlatformVersion",
                ( engine == "fargate" && platformVersion?upper_case != "LATEST" ),
                platformVersion?upper_case
            ) +
            attributeIfContent(
                "NetworkConfiguration",
                networkConfiguration
            ) +
            attributeIfTrue(
                "PlacementConstraints",
                (engine != "fargate") && (placementConstraints?size > 0),
                placementConstraints
            )
        dependencies=dependencies
        outputs=ECS_SERVICE_OUTPUT_MAPPINGS
    /]
[/#macro]

[#macro createECSCapacityProvider
        id
        asgId
        managedScaling=true
        minStepSize=1
        maxStepSize=10000
        targetCapacity=90
        managedTermination=true
        tags={}
        dependencies=[] ]

    [@cfResource
        id=id
        type="AWS::ECS::CapacityProvider"
        outputs=ECS_CAPACITYPROVIDER_OUTPUT_MAPPINGS
        tags=tags
        properties={
            "AutoScalingGroupProvider" : {
                "AutoScalingGroupArn" : getReference(asgId),
                "ManagedTerminationProtection" :
                        managedTermination?then(
                            "ENABLED",
                            "DISABLED"
                        ),
                "ManagedScaling" :
                    valueIfTrue(
                        {
                            "Status" : "ENABLED",
                            "MinimumScalingStepSize" : minStepSize,
                            "MaximumScalingStepSize" : maxStepSize,
                            "TargetCapacity" : targetCapacity
                        },
                        managedScaling,
                        {
                            "Status" : "DISABLED"
                        }
                    )
            }
        }
        dependencies=dependencies

    /]
[/#macro]
