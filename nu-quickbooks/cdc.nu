# Change Data Capture (CDC) commands for QuickBooks Online.
# Returns entities that have changed since a given timestamp.

use util.nu [ qb-call ]

# Fetch entities that have changed since a given timestamp.
#
# Pass a comma-separated list of entity names and an ISO 8601 timestamp.
# Returns the CDC response with changed records grouped by entity type.
@example "get changed invoices since Jan 2024" {
    qb cdc "Invoice" "2024-01-01T00:00:00-00:00"
}
@example "get changed customers and invoices" {
    qb cdc "Customer,Invoice" "2024-01-01T00:00:00-00:00"
}
export def "qb cdc" [
    entities: string        # Comma-separated entity names (e.g. "Customer,Invoice")
    changed_since: string   # ISO 8601 timestamp (e.g. "2024-01-01T00:00:00-00:00")
] {
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/cdc"

    qb-call "GET" $url --params {entities: $entities, changedSince: $changed_since}
}
