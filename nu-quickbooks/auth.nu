# Authentication commands for QuickBooks Online.
# Supports direct access token and full OAuth2 refresh flow.

use util.nu [ build-session refresh-access-token ]

# Log in to QuickBooks Online and set $env.QUICKBOOKS.
#
# Supports two modes:
# 1. Direct token:
#      qb login --access-token TOKEN --company-id 12345
# 2. Full OAuth2 (will auto-refresh the access token):
#      qb login --client-id CID --client-secret SEC --refresh-token RT --company-id 12345
@example "login with a direct access token" {
    qb login --access-token "eyJ..." --company-id "1234567890"
}
@example "login with OAuth2 credentials (auto-refresh)" {
    qb login --client-id "ABc..." --client-secret "XYz..." --refresh-token "AB1..." --company-id "1234567890"
}
@example "login to sandbox environment" {
    qb login --access-token "eyJ..." --company-id "1234567890" --sandbox
}
export def --env "qb login" [
    --access-token: string    # OAuth2 access token (direct login)
    --refresh-token: string   # OAuth2 refresh token
    --client-id: string       # OAuth2 client ID
    --client-secret: string   # OAuth2 client secret
    --company-id: string      # QuickBooks company (realm) ID
    --sandbox                 # Use the sandbox API environment
    --minorversion: int       # QBO API minor version (default: 75)
] {
    let mv = if ($minorversion != null) { $minorversion } else { 75 }

    if ($company_id == null) {
        error make {msg: "You must provide --company-id"}
    }

    if ($access_token != null) {
        # Direct token login
        $env.QUICKBOOKS = (
            build-session $access_token $company_id
            --sandbox=$sandbox
            --minorversion $mv
            --client-id $client_id
            --client-secret $client_secret
            --refresh-token $refresh_token
        )
        let env_label = if $sandbox { "sandbox" } else { "production" }
        print $"(ansi green)✓(ansi reset) Logged in to QuickBooks \(($env_label)\) — company ($company_id)"
        return
    }

    if ($client_id == null or $client_secret == null or $refresh_token == null) {
        error make {msg: "You must provide either --access-token or --client-id/--client-secret/--refresh-token"}
    }

    # OAuth2 refresh flow — get a fresh access token
    # We need a temporary session to call refresh-access-token
    $env.QUICKBOOKS = (
        build-session "placeholder" $company_id
        --sandbox=$sandbox
        --minorversion $mv
        --client-id $client_id
        --client-secret $client_secret
        --refresh-token $refresh_token
    )

    let token_response = (refresh-access-token)
    let new_access_token = $token_response.access_token
    let new_refresh_token = ($token_response.refresh_token? | default $refresh_token)

    $env.QUICKBOOKS = (
        build-session $new_access_token $company_id
        --sandbox=$sandbox
        --minorversion $mv
        --client-id $client_id
        --client-secret $client_secret
        --refresh-token $new_refresh_token
    )
    let env_label = if $sandbox { "sandbox" } else { "production" }
    print $"(ansi green)✓(ansi reset) Logged in to QuickBooks \(($env_label)\) — company ($company_id) \(OAuth2 refresh\)"
}

# Clear the QuickBooks session.
@example "log out of QuickBooks" { qb logout }
export def --env "qb logout" [] {
    if ("QUICKBOOKS" not-in $env) {
        print "Not logged in."
        return
    }
    $env.QUICKBOOKS = null
    print $"(ansi yellow)✓(ansi reset) Logged out of QuickBooks"
}

# Show current QuickBooks session information.
@example "show session info" { qb whoami }
export def "qb whoami" [] {
    if ("QUICKBOOKS" not-in $env or $env.QUICKBOOKS == null) {
        print "Not logged in. Use `qb login` first."
        return
    }

    let qb = $env.QUICKBOOKS
    {
        company_id: $qb.company_id
        sandbox: $qb.sandbox
        minorversion: $qb.minorversion
        api_url: $qb.api_url
        has_refresh_token: ($qb.refresh_token != null)
    }
}

# Refresh the current access token using stored OAuth2 credentials.
#
# Updates $env.QUICKBOOKS with the new token. Requires that you initially
# logged in with --client-id, --client-secret, and --refresh-token.
@example "refresh your access token" { qb refresh }
export def --env "qb refresh" [] {
    if ("QUICKBOOKS" not-in $env or $env.QUICKBOOKS == null) {
        error make {msg: "Not logged in. Use `qb login` first."}
    }

    let token_response = (refresh-access-token)
    let qb = $env.QUICKBOOKS

    let new_refresh = ($token_response.refresh_token? | default $qb.refresh_token)

    $env.QUICKBOOKS = (
        build-session $token_response.access_token $qb.company_id
        --sandbox=$qb.sandbox
        --minorversion $qb.minorversion
        --client-id $qb.client_id
        --client-secret $qb.client_secret
        --refresh-token $new_refresh
    )
    print $"(ansi green)✓(ansi reset) Access token refreshed"
}
