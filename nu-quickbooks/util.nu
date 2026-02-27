# Shared utility helpers for the nu-quickbooks module.
# These are internal helpers — not exported from the module root.

const MINIMUM_MINOR_VERSION = 75

const SANDBOX_API_URL = "https://sandbox-quickbooks.api.intuit.com/v3"
const PRODUCTION_API_URL = "https://quickbooks.api.intuit.com/v3"
const TOKEN_URL = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"

const BUSINESS_OBJECTS = [
    "Account", "Attachable", "Bill", "BillPayment",
    "Class", "CreditMemo", "Customer", "CustomerType", "CompanyCurrency",
    "Department", "Deposit", "Employee", "Estimate", "ExchangeRate", "Invoice",
    "Item", "JournalEntry", "Payment", "PaymentMethod", "Preferences",
    "Purchase", "PurchaseOrder", "RefundReceipt",
    "SalesReceipt", "TaxAgency", "TaxCode", "TaxService/Taxcode", "TaxRate", "Term",
    "TimeActivity", "Transfer", "Vendor", "VendorCredit", "CreditCardPayment",
    "RecurringTransaction"
]

# Build the session record stored in $env.QUICKBOOKS.
export def build-session [
    access_token: string
    company_id: string
    --sandbox                      # Use sandbox API
    --minorversion: int = 75       # QBO minor version
    --client-id: string            # OAuth2 client ID (for refresh)
    --client-secret: string        # OAuth2 client secret (for refresh)
    --refresh-token: string        # OAuth2 refresh token
] {
    let api_url = if $sandbox { $SANDBOX_API_URL } else { $PRODUCTION_API_URL }
    let base_url = $"($api_url)/company/($company_id)"

    {
        access_token: $access_token
        company_id: $company_id
        sandbox: $sandbox
        minorversion: $minorversion
        api_url: $api_url
        base_url: $base_url
        client_id: $client_id
        client_secret: $client_secret
        refresh_token: $refresh_token
        headers: (build-headers $access_token)
    }
}

# Build standard QBO REST API headers.
export def build-headers [access_token: string] {
    {
        Accept: "application/json"
        Authorization: $"Bearer ($access_token)"
        User-Agent: "nu-quickbooks"
    }
}

# Refresh the OAuth2 access token using the refresh token.
# Returns a record with the new access_token and refresh_token.
export def refresh-access-token [] {
    let qb = $env.QUICKBOOKS

    if ($qb.client_id == null or $qb.client_secret == null or $qb.refresh_token == null) {
        error make {msg: "Cannot refresh token: client_id, client_secret, and refresh_token are required. Log in with full OAuth2 credentials."}
    }

    let auth = ($"($qb.client_id):($qb.client_secret)" | encode base64)

    let response = (
        http post $TOKEN_URL
        {grant_type: "refresh_token", refresh_token: $qb.refresh_token}
        --content-type "application/x-www-form-urlencoded"
        --headers {
            Accept: "application/json"
            Authorization: $"Basic ($auth)"
        }
        --full
        --allow-errors
    )

    if $response.status != 200 {
        let detail = try { $response.body | to json } catch { $"($response.body)" }
        error make {msg: $"Token refresh failed \(HTTP ($response.status)\): ($detail)"}
    }

    $response.body
}

# Central HTTP helper for making QuickBooks API calls.
# Automatically injects minorversion query parameter.
# Returns the parsed response body.
export def qb-call [
    method: string
    url: string
    --data: any        # Body for POST requests
    --params: record   # Additional query parameters
    --content-type: string  # Override content type
] {
    let qb = $env.QUICKBOOKS
    let headers = $qb.headers

    # Build query string with minorversion
    let base_params = {minorversion: $"($qb.minorversion)"}
    let merged_params = if ($params != null) {
        $base_params | merge $params
    } else {
        $base_params
    }

    let query_string = (
        $merged_params
        | transpose key value
        | each {|kv| $"($kv.key)=($kv.value | into string | url encode)" }
        | str join "&"
    )
    let full_url = $"($url)?($query_string)"

    let ct = if ($content_type != null) { $content_type } else { "application/json" }

    let response = match ($method | str upcase) {
        "GET" => {
            http get $full_url --headers $headers --full --allow-errors
        }
        "POST" => {
            if ($data != null) {
                let body = if ($data | describe | str starts-with "string") {
                    $data
                } else {
                    $data | to json
                }
                http post $full_url $body --headers $headers --content-type $ct --full --allow-errors
            } else {
                http post $full_url "" --headers $headers --content-type $ct --full --allow-errors
            }
        }
        "DELETE" => {
            http delete $full_url --headers $headers --full --allow-errors
        }
        _ => {
            error make {msg: $"Unsupported HTTP method: ($method)"}
        }
    }

    let status = $response.status
    let body = $response.body

    # Handle QBO Fault responses
    if $status >= 300 {
        qb-error $status $url $body
    }

    # 204 No Content
    if $status == 204 {
        return null
    }

    $body
}

# Raise a structured QuickBooks error based on status code and QBO error codes.
export def qb-error [status: int url: string content: any] {
    # Try to extract QBO fault details
    let fault_info = try {
        let fault = $content.Fault?
        if ($fault != null) {
            let errors = ($fault.Error? | default [])
            let messages = ($errors | each {|e|
                let code = ($e.code? | default "")
                let msg = ($e.Message? | default "")
                let detail = ($e.Detail? | default "")
                $"  Code ($code): ($msg) — ($detail)"
            } | str join "\n")
            $messages
        } else {
            null
        }
    } catch {
        null
    }

    let status_msg = match $status {
        401 => "QuickBooks: Authentication failed or session expired"
        403 => "QuickBooks: Request refused — check permissions"
        404 => "QuickBooks: Resource not found"
        400 => "QuickBooks: Malformed request"
        _ => $"QuickBooks: API error \(($status)\)"
    }

    let detail = if ($fault_info != null) {
        $fault_info
    } else if ($content | describe) == "string" {
        $content
    } else {
        try { $content | to json } catch { $"($content)" }
    }

    error make {msg: $"($status_msg)\nURL: ($url)\nResponse: ($detail)"}
}

# Validate that an entity name is a known QBO business object.
export def validate-entity [entity: string] {
    if ($entity not-in $BUSINESS_OBJECTS) {
        error make {msg: $"\"($entity)\" is not a valid QuickBooks business object.\nValid objects: ($BUSINESS_OBJECTS | str join ', ')"}
    }
}

# Loads environment variables from a file.
export def --env load-env-file [path?: path = '.env'] {
    if ($path | path exists) {
        open -r $path | from kv | load-env
    } else {
        error make -u {msg: $'file `($path)` not found'}
    }
}

# Parses `KEY=value` text into a record.
export def 'from kv' []: oneof<string, nothing> -> record {
    default ''
    | parse '{key}={value}'
    | update value { from yaml }
    | transpose -dlr
    | default -e {}
}
