[#ftl]

[#function firehoseStreamProducePermission id]
    [#return
        [
            getPolicyStatement(
                [
                    "firehose:PutRecord",
                    "firehose:PutRecordBatch"
                ],
                getReference(id, ARN_ATTRIBUTE_TYPE)
            )
        ]
    ]
[/#function]

[#function firehoseStreamCloudwatchPermission id]
    [#return
        [
            getPolicyStatement(
                [
                    "firehose:DeleteDeliveryStream",
                    "firehose:PutRecord",
                    "firehose:PutRecordBatch",
                    "firehose:UpdateDestination"
                ],
                getReference(id, ARN_ATTRIBUTE_TYPE)
            )
        ]
    ]
[/#function]

[#function firehoseKinesisDataStreamPermssion id]
    [#return [
        getPolicyStatement(
            [
                "kinesis:DescribeStream",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:ListShards"
            ],
            getReference(id, ARN_ATTRIBUTE_TYPE)
        )
    ]]
[/#function]