# Permission Set Merger

A Salesforce Lightning Web Component (LWC) that lets you select multiple Permission Sets and merge them into a single new one — built for admins who manage complex permission structures and need to consolidate without manually recreating everything.

---

## Why This Exists

Anyone who has managed Salesforce permissions knows the pain. Over time, orgs accumulate dozens of permission sets — some overlapping, some redundant, some created for a single project that never got cleaned up. When you need to consolidate them, Salesforce gives you no native way to do it. You are left copying permissions one by one, object by object, field by field.

This tool fixes that.

---

## What It Does

Select 2 or more permission sets from your org and merge them into a brand new permission set in seconds. Everything is merged automatically — you just pick the sources, give the new one a name, and click merge.

**Object Permissions**
Read, Create, Edit, Delete, View All, and Modify All access for every object — merged additively so the result gets the highest access level from any source.

**Field Permissions**
Read and Edit access for every field across all selected permission sets — merged in a single query, no per-object loops.

**Tab Visibility**
Tab settings merged across all sources. Visible beats Available beats None. Tabs that do not exist in the target org are silently skipped.

**System and App Permissions**
All 139 standard boolean permission fields on the PermissionSet object — including permissions like Modify All Data, API Enabled, Author Apex, and all App-specific permissions — merged at insert time.

**Apex Class Access**
Every Apex class granted in any source permission set is included in the merged result.

**Visualforce Page Access**
Every VF page granted in any source is carried over.

**Flow Access**
All Flow definitions accessible in any source permission set.

**Named Credentials, External Data Sources, External Credential Principals**
All carried over from source permission sets.

**Connected Apps and Assigned Apps**
All app assignments from every source permission set.

**Custom Permissions, Custom Metadata Types, Custom Setting Definitions**
All included automatically.

**Service Presence Status Access and Service Providers (SSO)**
Merged via SetupEntityAccess.

**Data Category Visibility**
Merged automatically if Salesforce Knowledge is enabled in your org. Silently skipped if not.

---

## Getting Started

### Prerequisites

- Salesforce CLI (sf) installed — https://developer.salesforce.com/tools/salesforcecli
- A Salesforce org (Developer Edition, Sandbox, or Production)
- VS Code with Salesforce Extension Pack (optional but recommended)

### Deploy via CLI

```bash
# Authenticate to your org
sf org login web --alias myOrg

# Deploy
sf project deploy start --source-dir force-app --target-org myOrg

# Run tests
sf apex run test --class-names PermissionSetMergerControllerTest --target-org myOrg --result-format human
```

### Deploy via Workbench

1. Zip the `force-app` folder
2. Go to https://workbench.developerforce.com
3. Migration > Deploy > upload the zip
4. Check Run All Tests and click Next > Deploy

### Deploy via VS Code

1. Open this folder in VS Code
2. Press Ctrl+Shift+P and select SFDX: Authorize an Org
3. Right-click `force-app/main/default` and click Deploy Source to Org

---

## Adding It to a Page

1. Go to Setup > App Builder
2. Open any App Page or Home Page
3. Find `permissionSetMerger` under Custom Components in the left panel
4. Drag it onto the page
5. Save and Activate

Or add it as a standalone tab:

1. Setup > Tabs > Lightning Component Tabs > New
2. Lightning Component: `c:permissionSetMerger`
3. Tab Label: `Permission Set Merger`
4. Save and add to your app

---

## How to Use It

**Step 1 — Select Permission Sets**
Browse the available list on the left. Click to highlight, then use Add Selected or Add All to move them to the right panel. You need at least 2. Use the search box to filter by name.

**Step 2 — Name Your Permission Set**
Enter a Label. The API Name is auto-generated from the label but you can edit it. Add an optional description — if left blank, one is generated automatically listing the source permission sets.

**Step 3 — Review and Merge**
Check the summary of what will be merged. Note the 3 items that require manual setup after the merge. Click Merge Permission Sets. A detailed success and warning report is shown when complete.

---

## Project Structure

```
permission-set-merger/
├── README.md
├── sfdx-project.json
└── force-app/
    └── main/
        └── default/
            ├── classes/
            │   ├── PermissionSetMergerController.cls
            │   ├── PermissionSetMergerController.cls-meta.xml
            │   ├── PermissionSetMergerControllerTest.cls
            │   └── PermissionSetMergerControllerTest.cls-meta.xml
            └── lwc/
                └── permissionSetMerger/
                    ├── permissionSetMerger.html
                    ├── permissionSetMerger.js
                    ├── permissionSetMerger.css
                    └── permissionSetMerger.js-meta.xml
```

---

## Permissions Required

The user running this tool needs one of the following:

- Manage Profiles and Permission Sets
- Modify All Data
- System Administrator profile

---

## Technical Notes

- **without sharing** — PermissionSet and all related objects are setup objects. Using with sharing blocks DML on them entirely, which is why the class runs without sharing.
- **Permissions on INSERT** — System permission boolean fields must be set at insert time. Many are not updateable after the record is created, so they are all written in the initial insert.
- **Hardcoded permission field list** — Using Schema.DescribeFieldResult in a loop over 400+ fields was the main cause of CPU timeouts. The list is hardcoded and validated against the org's Schema at runtime to handle fields that do not exist in certain editions.
- **Single SOQL per section** — All permission types use one query regardless of how many permission sets are being merged. The SetupEntityAccess section uses a single query with SetupEntityType IN (...) instead of 13 separate queries.
- **Chunked DML** — All inserts are chunked at 200 records to respect Salesforce DML row limits.
- **Partial success** — Uses Database.insert(records, false) so a single bad record never aborts the entire section. Tab settings that reference tabs not enabled in the org are skipped and counted separately.

---

## Known Limitations

**Standard Invocable Action Type Access** — No Apex DML path exists. Configure manually in Setup after the merge.

**Org-Wide Email Address Access** — Not controlled by permission sets. Configure at the profile or user level.

**Email-to-Case Routing Address Access** — Requires Metadata API. Configure manually in Setup after the merge.

**Managed package permission sets** — Excluded from the selection list. Namespace-prefixed fields and classes cannot be reliably merged into a new permission set without the same namespace.

**Tab settings not in the org** — Silently skipped. If a source permission set references a tab from a feature not enabled in your org, that tab is skipped and reported in the results.

---

## Contributing

Found a bug? Have an idea? Pull requests are welcome.

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/your-idea`
3. Make your changes
4. Push and open a Pull Request

---

## License

MIT — use it, modify it, share it.

Built out of frustration at having no native way to consolidate Salesforce permission sets.
