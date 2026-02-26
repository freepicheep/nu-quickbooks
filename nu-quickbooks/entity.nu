# Entity CRUD commands for QuickBooks Online.
# Generic operations that work with any QBO business object type.

use util.nu [ qb-call validate-entity ]

# Get a QuickBooks entity by its ID.
@example "get a customer by ID" { qb get Customer 1 }
@example "get an invoice by ID" { qb get Invoice 42 }
export def "qb get" [
    entity: string   # Entity type (e.g. Customer, Invoice, Item)
    id: any          # The entity ID
] {
    validate-entity $entity
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/($entity | str downcase)/($id)"

    let result = (qb-call "GET" $url)

    # QBO wraps the response in the entity name key
    if ($entity in ($result | columns)) {
        $result | get $entity
    } else {
        $result
    }
}

# Create a new QuickBooks entity.
#
# Accepts data as a record argument or piped input.
# Returns the created entity record.
@example "create a customer" { qb create Customer {DisplayName: "Acme Corp", CompanyName: "Acme"} }
@example "create a customer via pipe" { {DisplayName: "Acme Corp"} | qb create Customer }
export def "qb create" [
    entity: string     # Entity type (e.g. Customer, Invoice)
    data?: record      # Entity data to create. Can also be piped in.
] {
    validate-entity $entity
    let input = $in
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/($entity | str downcase)"

    let body = if ($data != null) { $data } else { $input }

    if ($body == null) {
        error make {msg: "No data provided. Pass a record as an argument or pipe it in."}
    }

    let result = (qb-call "POST" $url --data $body)

    if ($entity in ($result | columns)) {
        $result | get $entity
    } else {
        $result
    }
}

# Update an existing QuickBooks entity.
#
# The data record MUST include Id and SyncToken fields.
# Returns the updated entity record.
@example "update a customer" { qb update Customer {Id: "1", SyncToken: "0", DisplayName: "New Name"} }
@example "update via pipe" { {Id: "1", SyncToken: "0", CompanyName: "Updated"} | qb update Customer }
export def "qb update" [
    entity: string     # Entity type (e.g. Customer, Invoice)
    data?: record      # Entity data with Id and SyncToken. Can also be piped in.
] {
    validate-entity $entity
    let input = $in
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/($entity | str downcase)"

    let body = if ($data != null) { $data } else { $input }

    if ($body == null) {
        error make {msg: "No data provided. Pass a record as an argument or pipe it in."}
    }

    if ("Id" not-in ($body | columns) or "SyncToken" not-in ($body | columns)) {
        error make {msg: "Update data must include 'Id' and 'SyncToken' fields."}
    }

    let result = (qb-call "POST" $url --data $body)

    if ($entity in ($result | columns)) {
        $result | get $entity
    } else {
        $result
    }
}

# Delete a QuickBooks entity.
#
# The data record MUST include Id and SyncToken fields.
@example "delete a payment" { qb delete Payment {Id: "5", SyncToken: "1"} }
@example "delete via pipe" { {Id: "5", SyncToken: "1"} | qb delete Bill }
export def "qb delete" [
    entity: string     # Entity type (e.g. Payment, Bill)
    data?: record      # Record with Id and SyncToken. Can also be piped in.
] {
    validate-entity $entity
    let input = $in
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/($entity | str downcase)"

    let body = if ($data != null) { $data } else { $input }

    if ($body == null) {
        error make {msg: "No data provided. Pass a record as an argument or pipe it in."}
    }

    if ("Id" not-in ($body | columns) or "SyncToken" not-in ($body | columns)) {
        error make {msg: "Delete data must include 'Id' and 'SyncToken' fields."}
    }

    qb-call "POST" $url --data $body --params {operation: "delete"}
}

# Void a QuickBooks transaction (Invoice, Payment, SalesReceipt, BillPayment).
#
# The data record MUST include Id and SyncToken fields.
@example "void an invoice" { qb void Invoice {Id: "7", SyncToken: "3"} }
@example "void a payment" { qb void Payment {Id: "10", SyncToken: "2"} }
export def "qb void" [
    entity: string     # Entity type (Invoice, Payment, SalesReceipt, BillPayment)
    data?: record      # Record with Id and SyncToken. Can also be piped in.
] {
    let input = $in
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/($entity | str downcase)"

    let body = if ($data != null) { $data } else { $input }

    if ($body == null) {
        error make {msg: "No data provided. Pass a record as an argument or pipe it in."}
    }

    # Different entities use different void mechanisms
    let params = match $entity {
        "Payment" | "SalesReceipt" | "BillPayment" => {
            {operation: "update", include: "void"}
        }
        "Invoice" => {
            {operation: "void"}
        }
        _ => {
            {operation: "void"}
        }
    }

    # Build the minimal void payload
    let void_body = match $entity {
        "Payment" | "SalesReceipt" | "BillPayment" => {
            {Id: $body.Id, SyncToken: $body.SyncToken, sparse: true}
        }
        _ => {
            {Id: $body.Id, SyncToken: $body.SyncToken}
        }
    }

    qb-call "POST" $url --data $void_body --params $params
}

# Send an entity via email (e.g. an Invoice or Estimate).
@example "send an invoice" { qb send Invoice 7 }
@example "send an invoice to a specific email" { qb send Invoice 7 --to "customer@example.com" }
export def "qb send" [
    entity: string     # Entity type (e.g. Invoice, Estimate)
    id: any            # The entity ID
    --to: string       # Optional email address override
] {
    let qb = $env.QUICKBOOKS
    let endpoint = if ($to != null) {
        $"($qb.base_url)/($entity | str downcase)/($id)/send?sendTo=($to | url encode --all)"
    } else {
        $"($qb.base_url)/($entity | str downcase)/($id)/send"
    }

    qb-call "POST" $endpoint --content-type "application/octet-stream"
}

# Download a PDF of an entity (Invoice, Estimate, SalesReceipt, etc.).
#
# Returns the raw PDF bytes. Pipe to `save` to write to a file.
@example "download an invoice PDF" { qb pdf Invoice 7 | save invoice_7.pdf }
@example "download a sales receipt PDF" { qb pdf SalesReceipt 12 | save receipt.pdf }
export def "qb pdf" [
    entity: string     # Entity type (e.g. Invoice, SalesReceipt)
    id: any            # The entity ID
] {
    let qb = $env.QUICKBOOKS
    let url = $"($qb.base_url)/($entity | str downcase)/($id)/pdf"

    let query_string = $"minorversion=($qb.minorversion)"
    let full_url = $"($url)?($query_string)"

    let headers = {
        Content-Type: "application/pdf"
        Accept: "application/pdf, application/json"
        Authorization: $"Bearer ($qb.access_token)"
        User-Agent: "nu-quickbooks"
    }

    let response = (http get $full_url --headers $headers --full --allow-errors)

    if $response.status != 200 {
        if $response.status == 401 {
            error make {msg: "QuickBooks: Authentication failed or session expired"}
        }

        # Try to extract error from JSON response
        let error_detail = try {
            let json_body = ($response.body | from json)
            if ("Fault" in ($json_body | columns)) {
                $json_body | to json
            } else {
                $"HTTP ($response.status)"
            }
        } catch {
            $"HTTP ($response.status)"
        }

        error make {msg: $"Failed to download PDF: ($error_detail)"}
    }

    $response.body
}
