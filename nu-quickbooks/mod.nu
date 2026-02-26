# nu-quickbooks — A Nushell module for interacting with the QuickBooks Online API.
#
# Usage:
#   use nu-quickbooks *
#
#   # Authenticate
#   qb login --access-token "eyJ..." --company-id "1234567890"
#
#   # Query
#   qb query "SELECT * FROM Customer WHERE Active = true"
#
#   # CRUD
#   qb get Customer 1
#   qb create Customer {DisplayName: "Acme"}
#   qb update Customer {Id: "1", SyncToken: "0", DisplayName: "Updated"}
#   qb delete Payment {Id: "5", SyncToken: "1"}
#
#   # Batch
#   [{DisplayName: "A"}, {DisplayName: "B"}] | qb batch Customer --operation create
#
#   # Reports
#   qb report ProfitAndLoss

# Re-export all public commands from submodules
export use auth.nu *
export use query.nu *
export use entity.nu *
export use batch.nu *
export use cdc.nu *
export use util.nu [ load-env-file ]
