param([Parameter(Mandatory = $true)][string] $Owner)

$Submodules = @(
    @{ Path = 'handlers/queue-stream/common'; Repository = 'xmip-handler-queue-stream-common' },
    @{ Path = 'handlers/queue-stream/msmq'; Repository = 'xmip-handler-msmq' },
    @{ Path = 'handlers/queue-stream/rabbitmq'; Repository = 'xmip-handler-rabbitmq' },
    @{ Path = 'handlers/queue-stream/apache-kafka'; Repository = 'xmip-handler-kafka' },
    @{ Path = 'handlers/queue-stream/ibmmq'; Repository = 'xmip-handler-ibmmq' },
    @{ Path = 'handlers/queue-stream/amqp'; Repository = 'xmip-handler-amqp' },
    @{ Path = 'handlers/queue-stream/stomp'; Repository = 'xmip-handler-stomp' },
    @{ Path = 'handlers/queue-stream/azure-service-bus'; Repository = 'xmip-handler-azure-service-bus' },
    @{ Path = 'handlers/queue-stream/azure-event-grid'; Repository = 'xmip-handler-azure-event-grid' },
    @{ Path = 'handlers/queue-stream/azure-event-hubs'; Repository = 'xmip-handler-azure-event-hubs' },
    @{ Path = 'handlers/queue-stream/aws-sqs'; Repository = 'xmip-handler-aws-sqs' },
    @{ Path = 'handlers/queue-stream/aws-sns'; Repository = 'xmip-handler-aws-sns' },
    @{ Path = 'handlers/queue-stream/google-pubsub'; Repository = 'xmip-handler-google-pubsub' },
    @{ Path = 'handlers/queue-stream/nats'; Repository = 'xmip-handler-nats' },
    @{ Path = 'handlers/queue-stream/redis-streams'; Repository = 'xmip-handler-redis-streams' },
    @{ Path = 'handlers/file-transfer/as2'; Repository = 'xmip-handler-as2' },
    @{ Path = 'handlers/file-transfer/as4'; Repository = 'xmip-handler-as4' },
    @{ Path = 'handlers/file-transfer/oftp2'; Repository = 'xmip-handler-oftp2' },
    @{ Path = 'handlers/data-exchange/common'; Repository = 'xmip-handler-data-exchange-common' },
    @{ Path = 'handlers/data-exchange/edi'; Repository = 'xmip-handler-edi' },
    @{ Path = 'handlers/data-exchange/x12'; Repository = 'xmip-handler-x12' },
    @{ Path = 'handlers/data-exchange/edifact'; Repository = 'xmip-handler-edifact' },
    @{ Path = 'handlers/data-exchange/peppol'; Repository = 'xmip-handler-peppol' },
    @{ Path = 'handlers/data-exchange/ubl'; Repository = 'xmip-handler-ubl' },
    @{ Path = 'handlers/data-exchange/rosettanet'; Repository = 'xmip-handler-rosettanet' },
    @{ Path = 'handlers/healthcare/hl7'; Repository = 'xmip-handler-hl7' },
    @{ Path = 'handlers/healthcare/fhir'; Repository = 'xmip-handler-fhir' },
    @{ Path = 'handlers/healthcare/mllp'; Repository = 'xmip-handler-mllp' },
    @{ Path = 'handlers/healthcare/dicom'; Repository = 'xmip-handler-dicom' }
)

foreach ($Submodule in $Submodules) {
    $Url = "https://github.com/$Owner/$($Submodule.Repository).git"
    if (-not (Test-Path $Submodule.Path)) {
        git submodule add $Url $Submodule.Path
    }
}
