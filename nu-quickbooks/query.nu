# Query and report commands for QuickBooks Online.

use util.nu [ qb-call ]

# Run a QuickBooks query (QBO SQL).
#
# Returns the matching records as a table.
# Use --raw to get the full QueryResponse.
# Use --all to auto-paginate through all pages.
# Use --max-results and --start-position for manual pagination.
@example "query all active customers" { qb query "SELECT * FROM Customer WHERE Active = true" }
@example "query with pagination" { qb query "SELECT * FROM Invoice" --max-results 50 --start-position 1 }
@example "query all records (auto-paginate)" { qb query "SELECT * FROM Customer" --all }
@example "get raw response" { qb query "SELECT * FROM Customer MAXRESULTS 5" --raw }
export def "qb query" [
    select: string          # QBO SQL query string (e.g. "SELECT * FROM Customer")
    --all                   # Auto-paginate to fetch all records
    --raw                   # Return the raw QueryResponse
    --max-results: int      # Maximum results per page
    --start-position: int   # Starting position (1-based)
] {
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/query"

    # Build the full query with optional pagination clauses
    mut query = $select
    if ($start_position != null) {
        $query = $"($query) STARTPOSITION ($start_position)"
    }
    if ($max_results != null) {
        $query = $"($query) MAXRESULTS ($max_results)"
    }

    let result = (qb-call "POST" $url --data $query --content-type "application/text")
    let qr = $result.QueryResponse

    if $raw {
        return $qr
    }

    if $all {
        # Auto-paginate: re-query with increasing STARTPOSITION
        let total = ($qr.totalCount? | default 0)
        let page_size = if ($max_results != null) { $max_results } else { 100 }

        # Collect first page
        mut all_records = []
        # Find entity key in QueryResponse (skip metadata keys)
        let entity_keys = ($qr | columns | where {|c| $c not-in ["startPosition", "maxResults", "totalCount"]})
        let entity_key = if ($entity_keys | is-empty) { null } else { $entity_keys | first }

        if ($entity_key != null) {
            $all_records = ($qr | get $entity_key)
        }

        if ($total > ($all_records | length)) {
            mut pos = ($all_records | length) + 1
            while ($pos <= $total) {
                let page_query = $"($select) STARTPOSITION ($pos) MAXRESULTS ($page_size)"
                let page_result = (qb-call "POST" $url --data $page_query --content-type "application/text")
                let page_qr = $page_result.QueryResponse

                let page_keys = ($page_qr | columns | where {|c| $c not-in ["startPosition", "maxResults", "totalCount"]})
                if (not ($page_keys | is-empty)) {
                    let page_key = ($page_keys | first)
                    $all_records = ($all_records | append ($page_qr | get $page_key))
                }
                $pos = $pos + $page_size
            }
        }

        return $all_records
    }

    # Single page — extract entity records
    let entity_keys = ($qr | columns | where {|c| $c not-in ["startPosition", "maxResults", "totalCount"]})
    if ($entity_keys | is-empty) {
        return []
    }

    $qr | get ($entity_keys | first)
}

# Get the record count for an entity, with optional where clause.
#
# The where clause should NOT include the "WHERE" keyword.
@example "count all customers" { qb count Customer }
@example "count active customers" { qb count Customer "Active = true" }
@example "count invoices for a customer" { qb count Invoice "CustomerRef = '100'" }
export def "qb count" [
    entity: string          # Entity type (e.g. Customer, Invoice)
    where_clause?: string   # Optional WHERE clause (without 'WHERE')
] {
    let select = if ($where_clause != null) {
        $"SELECT COUNT\(*\) FROM ($entity) WHERE ($where_clause)"
    } else {
        $"SELECT COUNT\(*\) FROM ($entity)"
    }

    let result = (qb query $select --raw)
    $result.totalCount? | default 0
}

# Fetch a QuickBooks report.
#
# See Intuit documentation for available report types and parameters.
@example "get Profit and Loss report" { qb report ProfitAndLoss }
@example "get Balance Sheet with date range" { qb report BalanceSheet --params {start_date: "2024-01-01", end_date: "2024-12-31"} }
@example "get Trial Balance" { qb report TrialBalance }
export def "qb report" [
    report_type: string     # Report type (e.g. ProfitAndLoss, BalanceSheet, TrialBalance)
    --params: record        # Optional query parameters for the report
] {
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/reports/($report_type)"

    if ($params != null) {
        qb-call "GET" $url --params $params
    } else {
        qb-call "GET" $url
    }
}
