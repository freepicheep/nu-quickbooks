# nu-quickbooks

A [Nushell](https://www.nushell.sh/) module for interacting with the QuickBooks Online API. Query data, manage records, run reports, and perform batch operations without leaving your shell.

Ported from the excellent [python-quickbooks](https://github.com/ej2/python-quickbooks) library.

## Features

- **Authentication** — Log in via OAuth2 access token or full client credentials with auto-refresh.
- **Querying** — Run QBO SQL queries with built-in auto-pagination, get record counts.
- **Entity CRUD** — Create, read, update, delete, void, send, and download PDFs for any entity.
- **Batch Operations** — Create, update, or delete multiple records in a single request.
- **Reports** — Fetch Profit & Loss, Balance Sheet, Trial Balance, and other reports.
- **Change Data Capture** — Get entities that changed since a given timestamp.

## Installation

**Git Clone**

Clone this repository (or copy the `nu-quickbooks` directory) somewhere on your machine, then import it in your Nushell session or config:

```nu
use /path/to/nu-quickbooks *
```

**Using Quiver**

```nu
qv add freepicheep/nu-quickbooks
```

Then in your code:

```nu
use nu-quickbooks *
```

## Quick Start

```nu
# 1. Authenticate with a direct access token
qb login --access-token "eyJ..." --company-id "1234567890"

# Or authenticate with OAuth2 credentials (auto-refreshes the token)
qb login --client-id "ABc..." --client-secret "XYz..." --refresh-token "AB1..." --company-id "1234567890"

# 2. Query records
qb query "SELECT * FROM Customer WHERE Active = true"

# 3. Get a single record
qb get Customer 1

# 4. Create a record
qb create Customer {DisplayName: "Acme Corp", CompanyName: "Acme"}

# 5. Update a record
qb update Customer {Id: "1", SyncToken: "0", DisplayName: "Updated Name"}

# 6. Delete a record
qb delete Payment {Id: "5", SyncToken: "1"}

# 7. Void a transaction
qb void Invoice {Id: "7", SyncToken: "3"}

# 8. Download a PDF
qb pdf Invoice 42 | save invoice_42.pdf

# 9. Fetch a report
qb report ProfitAndLoss

# 10. Check your session
qb whoami

# 11. Refresh your token
qb refresh

# 12. Log out
qb logout
```

### Credential Management

Store your QuickBooks credentials in a `.env` file and load them:

**Your `.env` File**
```env
QB_ACCESS_TOKEN='eyJ...'
QB_COMPANY_ID='1234567890'
```

**In Your Script**
```nu
use /path/to/nu-quickbooks *

load-env-file
qb login --access-token $env.QB_ACCESS_TOKEN --company-id $env.QB_COMPANY_ID
```

### Sandbox Environment

To use the QBO sandbox, add the `--sandbox` flag:

```nu
qb login --access-token "eyJ..." --company-id "1234567890" --sandbox
```

## Commands

| Command | Description |
| --- | --- |
| `qb login` | Authenticate to QuickBooks Online |
| `qb logout` | Clear the current session |
| `qb whoami` | Show session information |
| `qb refresh` | Refresh the OAuth2 access token |
| `qb query` | Run a QBO SQL query |
| `qb count` | Get record count for an entity |
| `qb report` | Fetch a QuickBooks report |
| `qb get` | Get an entity by ID |
| `qb create` | Create a new entity |
| `qb update` | Update an existing entity |
| `qb delete` | Delete an entity |
| `qb void` | Void a transaction |
| `qb send` | Send an entity via email |
| `qb pdf` | Download a PDF of an entity |
| `qb batch` | Batch create/update/delete |
| `qb cdc` | Change data capture |
| `load-env-file` | Load key-value data from a .env file |

## Learning More

Every command has built-in documentation. Use `help` to view descriptions, flags, and examples:

```nu
help qb query
help qb create
help qb login
```

## QuickBooks OAuth2

This module requires OAuth2 tokens obtained through Intuit's developer portal. Follow the [OAuth 2.0 Guide](https://developer.intuit.com/app/developer/qbo/docs/develop/authentication-and-authorization/oauth-2.0) to get your tokens.

## API Minor Version

Beginning August 1, 2025, Intuit is deprecating support for minor versions 1–74. This module defaults to minor version 75. You can override it with `--minorversion` on login. See [Intuit's announcement](https://blogs.intuit.com/2025/01/21/changes-to-our-accounting-api-that-may-impact-your-application/) for details.

## Disclaimers

This module was ported from [python-quickbooks](https://github.com/ej2/python-quickbooks) and adapted for Nushell's record-based paradigm. Not all features have been fully tested. Use at your own risk.

## License

MIT
