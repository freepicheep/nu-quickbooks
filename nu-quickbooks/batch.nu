# Batch operation commands for QuickBooks Online.
# Enables creating, updating, or deleting multiple records in a single request.

use util.nu [ qb-call ]

# Run a batch operation on a list of records.
#
# Pipe in a list of records and specify the entity type and operation.
# Records are automatically chunked into batches of 30 (QBO maximum).
# Returns the combined batch response.
@example "batch create customers" {
    [{DisplayName: "Acme"}, {DisplayName: "Globex"}] | qb batch Customer --operation create
}
@example "batch delete payments" {
    [{Id: "1", SyncToken: "0"}, {Id: "2", SyncToken: "1"}] | qb batch Payment --operation delete
}
export def "qb batch" [
    entity: string                             # Entity type (e.g. Customer, Invoice)
    --operation: string                        # Operation: create, update, or delete
    --max-batch-size: int = 30                 # Max items per batch request (QBO limit is 30)
] {
    let records = $in

    if ($records == null or ($records | is-empty)) {
        error make {msg: "No records provided. Pipe in a list of records."}
    }

    if ($operation not-in ["create", "update", "delete"]) {
        error make {msg: $"Invalid operation: ($operation). Must be 'create', 'update', or 'delete'."}
    }

    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/batch"

    # Process in chunks
    let chunks = ($records | chunks $max_batch_size)

    mut all_responses = []

    for chunk in $chunks {
        # Build BatchItemRequest payload
        let batch_items = ($chunk | enumerate | each {|item|
            let bid = $"bid-($item.index)"
            {
                bId: $bid
                operation: $operation
                ($entity): $item.item
            }
        })

        let batch_payload = { BatchItemRequest: $batch_items }
        let result = (qb-call "POST" $url --data $batch_payload)

        if ("BatchItemResponse" in ($result | columns)) {
            $all_responses = ($all_responses | append $result.BatchItemResponse)
        }
    }

    # Separate successes and faults
    let successes = ($all_responses | where {|r| "Fault" not-in ($r | columns) })
    let faults = ($all_responses | where {|r| "Fault" in ($r | columns) })

    {
        total: ($all_responses | length)
        successes: $successes
        faults: $faults
    }
}
