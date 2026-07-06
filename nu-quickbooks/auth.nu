# Authentication commands for QuickBooks Online.
# Supports direct access token, full OAuth2 refresh flow, and an in-shell
# browser-based authorization-code flow (no OAuth Playground needed).

use util.nu [ build-session refresh-access-token exchange-auth-code build-authorize-url DEFAULT_SCOPE ]

# Log in to QuickBooks Online and set $env.QUICKBOOKS.
#
# Supports three modes:
# 1. Direct token:
#      qb login --access-token TOKEN --realm-id 12345
# 2. Full OAuth2 (will auto-refresh the access token):
#      qb login --client-id CID --client-secret SEC --refresh-token RT --realm-id 12345
# 3. Browser authorization (fetches the refresh token for you):
#      qb login --client-id CID --client-secret SEC
#    Opens your browser to authorize, then exchanges the returned code for
#    tokens. The realm ID is read from the callback, so you don't pass it.
#    Your --redirect-uri must be registered in your Intuit app.
#
# Note: --realm-id is the Realm ID returned in the OAuth callback URL.
# This is different from your QuickBooks company name or number.
@example "login with a direct access token" {
    qb login --access-token "eyJ..." --realm-id "1234567890"
}
@example "login with OAuth2 credentials (auto-refresh)" {
    qb login --client-id "ABc..." --client-secret "XYz..." --refresh-token "AB1..." --realm-id "1234567890"
}
@example "login via the browser (fetches the refresh token for you)" {
    qb login --client-id "ABc..." --client-secret "XYz..."
}
@example "login to sandbox environment" {
    qb login --access-token "eyJ..." --realm-id "1234567890" --sandbox
}
export def --env "qb login" [
    --access-token: string    # OAuth2 access token (direct login)
    --refresh-token: string   # OAuth2 refresh token
    --client-id: string       # OAuth2 client ID
    --client-secret: string   # OAuth2 client secret
    --realm-id: string        # Realm ID from OAuth callback (used in API URLs)
    --redirect-uri: string = "http://localhost:8000/callback"  # Redirect URI registered in your Intuit app (browser flow)
    --scope: string           # OAuth2 scope (browser flow; default: accounting)
    --sandbox                 # Use the sandbox API environment
    --minorversion: int       # QBO API minor version (default: 75)
] {
    let mv = if ($minorversion != null) { $minorversion } else { 75 }

    if ($access_token != null) {
        if ($realm_id == null) {
            error make {msg: "You must provide --realm-id (the Realm ID from the OAuth callback URL)"}
        }

        # Direct token login
        $env.QUICKBOOKS = (
            build-session $access_token $realm_id
            --sandbox=$sandbox
            --minorversion $mv
            --client-id $client_id
            --client-secret $client_secret
            --refresh-token $refresh_token
        )
        let env_label = if $sandbox { "sandbox" } else { "production" }
        print $"(ansi green)✓(ansi reset) Logged in to QuickBooks \(($env_label)\) — realm ($realm_id)"
        return
    }

    if ($client_id == null or $client_secret == null) {
        error make {msg: "You must provide either --access-token, --client-id/--client-secret/--refresh-token, or --client-id/--client-secret (browser login)"}
    }

    if ($refresh_token != null) {
        if ($realm_id == null) {
            error make {msg: "You must provide --realm-id (the Realm ID from the OAuth callback URL)"}
        }

        # OAuth2 refresh flow — get a fresh access token
        # We need a temporary session to call refresh-access-token
        $env.QUICKBOOKS = (
            build-session "placeholder" $realm_id
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
            build-session $new_access_token $realm_id
            --sandbox=$sandbox
            --minorversion $mv
            --client-id $client_id
            --client-secret $client_secret
            --refresh-token $new_refresh_token
        )
        let env_label = if $sandbox { "sandbox" } else { "production" }
        print $"(ansi green)✓(ansi reset) Logged in to QuickBooks \(($env_label)\) — realm ($realm_id) \(OAuth2 refresh\)"
        return
    }

    # Browser authorization-code flow — fetches the refresh token for you.
    let state = (random uuid)
    let auth_url = (build-authorize-url $client_id $redirect_uri ($scope | default $DEFAULT_SCOPE) $state)

    print $"Opening your browser to authorize QuickBooks…"
    print $"If it doesn't open, visit this URL manually:\n($auth_url)\n"
    try { start $auth_url }

    let pasted = (input "After approving, paste the full redirect URL here: " | str trim)
    if ($pasted | is-empty) {
        error make {msg: "No redirect URL provided — login cancelled."}
    }

    let params = (
        $pasted | url parse | get params
        | reduce -f {} {|it, acc| $acc | insert $it.key $it.value }
    )

    if (($params.state? | default "") != $state) {
        error make {msg: "State mismatch in callback — aborting (possible CSRF or wrong URL pasted)."}
    }

    let code = ($params.code? | default "")
    if ($code | is-empty) {
        error make {msg: "No authorization `code` found in the pasted URL."}
    }

    let cb_realm = ($params.realmId? | default $realm_id)
    if ($cb_realm | is-empty) {
        error make {msg: "No realmId found in the callback and --realm-id was not provided."}
    }

    let token_response = (exchange-auth-code $client_id $client_secret $code $redirect_uri)

    $env.QUICKBOOKS = (
        build-session $token_response.access_token $cb_realm
        --sandbox=$sandbox
        --minorversion $mv
        --client-id $client_id
        --client-secret $client_secret
        --refresh-token $token_response.refresh_token
    )
    let env_label = if $sandbox { "sandbox" } else { "production" }
    print $"(ansi green)✓(ansi reset) Logged in to QuickBooks \(($env_label)\) — realm ($cb_realm) \(browser authorization\)"
    print $"Run `qb whoami` to view your session."
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
        realm_id: $qb.realm_id
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
        build-session $token_response.access_token $qb.realm_id
        --sandbox=$qb.sandbox
        --minorversion $qb.minorversion
        --client-id $qb.client_id
        --client-secret $qb.client_secret
        --refresh-token $new_refresh
    )
    print $"(ansi green)✓(ansi reset) Access token refreshed"
}
