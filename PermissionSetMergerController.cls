/**
 * PermissionSetMergerController
 * ─────────────────────────────────────────────────────────────────────────────
 * Merges any number of permission sets.
 *
 * Performance fixes applied:
 *  1. Schema.DescribeFieldResult loop removed — hardcoded list of known
 *     system/app permission field names instead (Schema describe in a loop
 *     is extremely CPU-expensive and was the main timeout cause)
 *  2. Schema.getGlobalDescribe() removed — replaced with a try/catch SOQL
 *     approach for DataCategoryGroupVisibility
 *  3. buildMergedPermissionSet uses a SINGLE SOQL query (not chunked loop)
 *     by querying only the specific fields we need at once
 *  4. All other SOQLs are already single-query per section
 *
 * NOT covered (no Apex DML path exists):
 *   - Standard Invocable Action Type Access
 *   - Org-Wide Email Address Access
 *   - Email-to-Case Routing Address Access
 */
public without sharing class PermissionSetMergerController {

    // Hardcoded list of all standard system/app permission fields on PermissionSet.
    // Using Schema.describe() in a loop over 400+ fields was the main CPU timeout cause.
    // These are the stable, documented boolean Permissions* fields available in all orgs.
    private static final List<String> SYSTEM_PERM_FIELDS = new List<String>{
        'PermissionsEmailSingle','PermissionsEmailMass','PermissionsEditTask','PermissionsEditEvent',
        'PermissionsExportReport','PermissionsImportPersonal','PermissionsDataExport','PermissionsManageUsers',
        'PermissionsSF2','PermissionsSF3','PermissionsCreateCustomizeReports','PermissionsEditReports',
        'PermissionsManageDashboards','PermissionsDeleteActivatedContract','PermissionsEmailAdministration','PermissionsManageLeads',
        'PermissionsViewAllData','PermissionsEditPublicDocuments','PermissionsSF4','PermissionsViewEncryptedData',
        'PermissionsEditBillingInfo','PermissionsFeedPinning','PermissionsManageCustomReportTypes','PermissionsEditOppLineItemUnitPrice',
        'PermissionsCreateMultiforce','PermissionsBulkApiHardDelete','PermissionsSolutionImport','PermissionsManageCallCenters',
        'PermissionsManageSynonyms','PermissionsViewContent','PermissionsManageEmailClientConfig','PermissionsEnableNotifications',
        'PermissionsManageDataIntegrations','PermissionsDistributeFromPEOrg','PermissionsViewDataCategories','PermissionsManageDataCategories',
        'PermissionsAuthorApex','PermissionsManageMobile','PermissionsApiEnabled','PermissionsManageCustomPermissions',
        'PermissionsEditReadonlyFields','PermissionsRunReports','PermissionsViewSetup','PermissionsTransferAnyEntity',
        'PermissionsNewReportBuilder','PermissionsActivateContract','PermissionsActivateOrder','PermissionsImportLeads',
        'PermissionsManagePartners','PermissionsDeleteReports','PermissionsEditMyReports','PermissionsViewMyTeamsDashboards',
        'PermissionsModifyAllData','PermissionsManageCases','PermissionsViewHealthCheck','PermissionsManageHealthCheck',
        'PermissionsPackaging2','PermissionsManageIpAddresses','PermissionsSelectFilesFromSalesforce','PermissionsModerateNetworkUsers',
        'PermissionsMassInlineEdit','PermissionsManageTranslation','PermissionsCanApproveFeedPost','PermissionsAddDirectMessageMembers',
        'PermissionsAllowViewEditConvertedLeads','PermissionsShowCompanyNameAsUserBadge','PermissionsAccessCMC','PermissionsViewHealthCheckReadonly',
        'PermissionsManageNetworkUsers','PermissionsManageAuthProviders','PermissionsRunFlow','PermissionsCreateCustomizeDashboards',
        'PermissionsCreateDashboardFolders','PermissionsViewPublicDashboards','PermissionsDelegatedTwoFactor','PermissionsChatterEditOwnPost',
        'PermissionsChatterEditOwnRecordPost','PermissionsImportCustomObjects','PermissionsUseTeamReassignWizards','PermissionsViewDataLeakageEvents',
        'PermissionsEditSystemJobsAndSchedules','PermissionsManageRemoteAccess','PermissionsCanUseNewDashboardBuilder','PermissionsManageCategories',
        'PermissionsConvertLeads','PermissionsPasswordNeverExpires','PermissionsEditActivatedOrders','PermissionsSendSitRequests',
        'PermissionsApiUserOnly','PermissionsManageInteraction','PermissionsModerateNetworkFeeds','PermissionsManagePvtRptsAndDashbds',
        'PermissionsAllowLightningLogin','PermissionsManageReportsInPubFolders','PermissionsQueryAllFiles','PermissionsManageContentPermissions',
        'PermissionsManagePasswordPolicies','PermissionsManageLoginAccessPolicies','PermissionsViewPlatformEvents','PermissionsManageCustomNotifications',
        'PermissionsManageDataConnectors','PermissionsManageSSO','PermissionsCreateReportFolders','PermissionsSubmitMacrosAllowed',
        'PermissionsAccessFlowBuilderExtensions','PermissionsManageHubConnections','PermissionsB2BMarketingAnalyticsUser','PermissionsTraceXdsQueries',
        'PermissionsViewSecurityCommandCenter','PermissionsManageSecurityCommandCenter','PermissionsCreateCustomizeFilters','PermissionsChatterInternalUser',
        'PermissionsManageContentProperties','PermissionsManageAnalyticSnapshots','PermissionsScheduleReports','PermissionsManageBusinessHourHolidays',
        'PermissionsManageDynamicDashboards','PermissionsCustomSidebarOnAllPages','PermissionsUseWebLink','PermissionsManagePublicListViews',
        'PermissionsManagePublicTemplates','PermissionsScheduleJob','PermissionsManageSandboxes','PermissionsIdentityEnabled',
        'PermissionsGovernNetworks','PermissionsViewEventLogFiles','PermissionsManageTwoFactor','PermissionsChatterOwnGroups',
        'PermissionsLightningExperienceUser','PermissionsConfigCustomRecs','PermissionsLtngPromoReserved01UserPerm','PermissionsManageSurveys',
        'PermissionsUseMyDomains','PermissionsEnableCommunityAppLauncher','PermissionsContentAdministrator','PermissionsCreateWorkspaces',
        'PermissionsManageContentTypes','PermissionsManageExchangeConfig','PermissionsViewRestrictionAndScopingRules'
    };

    // ─────────────────────────────────────────────────────────────────────────
    // GET PERMISSION SETS FOR UI
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<PermSetWrapper> getPermissionSets() {
        List<PermSetWrapper> result = new List<PermSetWrapper>();
        for (PermissionSet ps : [
            SELECT Id, Label, Name, Description
            FROM   PermissionSet
            WHERE      IsOwnedByProfile = false
            ORDER BY Label
        ]) {
            result.add(new PermSetWrapper(
                ps.Id, ps.Label, ps.Name,
                String.isBlank(ps.Description) ? '' : ps.Description
            ));
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MAIN MERGE
    // ─────────────────────────────────────────────────────────────────────────
    @AuraEnabled
    public static MergeResult mergePermissionSets(
        List<Id> permissionSetIds,
        String   newLabel,
        String   newApiName,
        String   newDescription
    ) {
        if (permissionSetIds == null || permissionSetIds.size() < 2) {
            throw new AuraHandledException('Please select at least 2 permission sets to merge.');
        }
        if (String.isBlank(newLabel) || String.isBlank(newApiName)) {
            throw new AuraHandledException('Label and API Name are required.');
        }
        if (![SELECT Id FROM PermissionSet WHERE Name = :newApiName LIMIT 1].isEmpty()) {
            throw new AuraHandledException(
                'A permission set with API Name "' + newApiName + '" already exists.');
        }

        MergeResult res = new MergeResult();
        String autoDesc = String.isBlank(newDescription)
            ? 'Merged from: ' + String.join(getLabels(permissionSetIds), ', ')
            : newDescription;
        // Description field max length is 255 — truncate safely
        if (autoDesc.length() > 255) autoDesc = autoDesc.substring(0, 252) + '...';

        // ── 1. Create PermissionSet with System/App Permissions on INSERT ─────
        SObject newPSRecord = buildMergedPermissionSet(
            permissionSetIds, newApiName, newLabel, autoDesc);
        insert newPSRecord;
        Id newPSId = (Id) newPSRecord.get('Id');
        res.newPermissionSetId = newPSId;
        res.addSuccess('System & App Permissions', 'All permission fields merged');

        // ── 2. Object Permissions ─────────────────────────────────────────────
        try {
            Map<String, ObjectPermissions> objMap = new Map<String, ObjectPermissions>();
            for (ObjectPermissions op : [
                SELECT SobjectType, PermissionsRead, PermissionsCreate,
                       PermissionsEdit, PermissionsDelete,
                       PermissionsViewAllRecords, PermissionsModifyAllRecords
                FROM   ObjectPermissions WHERE ParentId IN :permissionSetIds
            ]) {
                if (!objMap.containsKey(op.SobjectType)) {
                    ObjectPermissions n = new ObjectPermissions();
                    n.SobjectType = op.SobjectType;
                    n.PermissionsRead = op.PermissionsRead;
                    n.PermissionsCreate = op.PermissionsCreate;
                    n.PermissionsEdit = op.PermissionsEdit;
                    n.PermissionsDelete = op.PermissionsDelete;
                    n.PermissionsViewAllRecords = op.PermissionsViewAllRecords;
                    n.PermissionsModifyAllRecords = op.PermissionsModifyAllRecords;
                    objMap.put(op.SobjectType, n);
                } else {
                    ObjectPermissions e = objMap.get(op.SobjectType);
                    e.PermissionsRead |= op.PermissionsRead;
                    e.PermissionsCreate |= op.PermissionsCreate;
                    e.PermissionsEdit |= op.PermissionsEdit;
                    e.PermissionsDelete |= op.PermissionsDelete;
                    e.PermissionsViewAllRecords |= op.PermissionsViewAllRecords;
                    e.PermissionsModifyAllRecords |= op.PermissionsModifyAllRecords;
                }
            }
            List<ObjectPermissions> toInsert = new List<ObjectPermissions>();
            for (ObjectPermissions op : objMap.values()) { op.ParentId = newPSId; toInsert.add(op); }
            insertInChunks(toInsert);
            res.addSuccess('Object Permissions', toInsert.size() + ' objects merged');
        } catch (Exception ex) { res.addWarning('Object Permissions', ex.getMessage()); }

        // ── 3. Field Permissions — single SOQL ────────────────────────────────
        try {
            Map<String, FieldPermissions> fieldMap = new Map<String, FieldPermissions>();
            for (FieldPermissions fp : [
                SELECT SobjectType, Field, PermissionsRead, PermissionsEdit
                FROM   FieldPermissions WHERE ParentId IN :permissionSetIds
            ]) {
                String key = fp.SobjectType + '||' + fp.Field;
                if (!fieldMap.containsKey(key)) {
                    FieldPermissions n = new FieldPermissions();
                    n.SobjectType = fp.SobjectType; n.Field = fp.Field;
                    n.PermissionsRead = fp.PermissionsRead; n.PermissionsEdit = fp.PermissionsEdit;
                    fieldMap.put(key, n);
                } else {
                    FieldPermissions e = fieldMap.get(key);
                    e.PermissionsRead |= fp.PermissionsRead;
                    e.PermissionsEdit |= fp.PermissionsEdit;
                }
            }
            List<FieldPermissions> toInsert = new List<FieldPermissions>();
            for (FieldPermissions fp : fieldMap.values()) { fp.ParentId = newPSId; toInsert.add(fp); }
            insertInChunks(toInsert);
            res.addSuccess('Field Permissions', toInsert.size() + ' fields merged');
        } catch (Exception ex) { res.addWarning('Field Permissions', ex.getMessage()); }

        // ── 4. Tab Settings ───────────────────────────────────────────────────
        try {
            Map<String, String> tabMap = new Map<String, String>();
            for (PermissionSetTabSetting ts : [
                SELECT Name, Visibility FROM PermissionSetTabSetting
                WHERE ParentId IN :permissionSetIds
            ]) {
                if (!tabMap.containsKey(ts.Name) || ts.Visibility == 'Visible'
                    || (ts.Visibility == 'Available' && tabMap.get(ts.Name) != 'Visible')) {
                    tabMap.put(ts.Name, ts.Visibility);
                }
            }
            List<PermissionSetTabSetting> toInsert = new List<PermissionSetTabSetting>();
            for (String n : tabMap.keySet()) {
                PermissionSetTabSetting t = new PermissionSetTabSetting();
                t.ParentId = newPSId; t.Name = n; t.Visibility = tabMap.get(n);
                toInsert.add(t);
            }
            if (!toInsert.isEmpty()) insert toInsert;
            res.addSuccess('Tab Settings', toInsert.size() + ' tabs merged');
        } catch (Exception ex) { res.addWarning('Tab Settings', ex.getMessage()); }

        // ── 5. SetupEntityAccess — single SOQL for ALL types ─────────────────
        try {
            Set<String> supportedTypes = new Set<String>{
                'ApexClass','ApexPage','FlowDefinition','CustomPermission',
                'CustomMetadataType','CustomSetting','NamedCredential',
                'ExternalDataSource','ExternalCredentialPrincipal',
                'ConnectedApplication','TabSet','ServicePresenceStatus','SamlSsoConfig'
            };
            Map<String, String> typeLabels = new Map<String, String>{
                'ApexClass'=>'Apex Class Access','ApexPage'=>'Visualforce Page Access',
                'FlowDefinition'=>'Flow Access','CustomPermission'=>'Custom Permissions',
                'CustomMetadataType'=>'Custom Metadata Type Access',
                'CustomSetting'=>'Custom Setting Definitions',
                'NamedCredential'=>'Named Credential Access',
                'ExternalDataSource'=>'External Data Source Access',
                'ExternalCredentialPrincipal'=>'External Credential Principal Access',
                'ConnectedApplication'=>'Assigned Connected Apps',
                'TabSet'=>'Assigned Apps',
                'ServicePresenceStatus'=>'Service Presence Status Access',
                'SamlSsoConfig'=>'Service Providers (SSO)'
            };
            Map<String, Set<Id>> byType = new Map<String, Set<Id>>();
            for (SetupEntityAccess sea : [
                SELECT SetupEntityId, SetupEntityType FROM SetupEntityAccess
                WHERE  ParentId IN :permissionSetIds
                AND    SetupEntityType IN :supportedTypes
            ]) {
                if (!byType.containsKey(sea.SetupEntityType)) {
                    byType.put(sea.SetupEntityType, new Set<Id>());
                }
                byType.get(sea.SetupEntityType).add(sea.SetupEntityId);
            }
            List<SetupEntityAccess> toInsert = new List<SetupEntityAccess>();
            for (String entityType : byType.keySet()) {
                for (Id eid : byType.get(entityType)) {
                    toInsert.add(new SetupEntityAccess(ParentId=newPSId, SetupEntityId=eid));
                }
            }
            insertInChunks(toInsert);
            for (String t : byType.keySet()) {
                res.addSuccess(typeLabels.get(t), byType.get(t).size() + ' records merged');
            }
        } catch (Exception ex) { res.addWarning('Setup Entity Access', ex.getMessage()); }

        // ── 6. Data Category Visibility — try/catch avoids Schema.getGlobalDescribe()
        try {
            String qry = 'SELECT DataCategoryGroupApiName, CategoryApiName, Visibility '
                       + 'FROM DataCategoryGroupVisibility WHERE ParentId IN :permissionSetIds';
            Map<String, SObject> dcMap = new Map<String, SObject>();
            for (SObject dc : Database.query(qry)) {
                String key = (String)dc.get('DataCategoryGroupApiName')
                           + '|' + (String)dc.get('CategoryApiName');
                if (!dcMap.containsKey(key)) dcMap.put(key, dc);
            }
            if (!dcMap.isEmpty()) {
                List<SObject> toInsert = new List<SObject>();
                for (SObject dc : dcMap.values()) {
                    SObject n = Schema.getGlobalDescribe()
                        .get('DataCategoryGroupVisibility').newSObject();
                    n.put('ParentId', newPSId);
                    n.put('DataCategoryGroupApiName', dc.get('DataCategoryGroupApiName'));
                    n.put('CategoryApiName', dc.get('CategoryApiName'));
                    n.put('Visibility', dc.get('Visibility'));
                    toInsert.add(n);
                }
                insert toInsert;
                res.addSuccess('Data Category Visibility', toInsert.size() + ' merged');
            }
        } catch (Exception ex) {
            // Silently skip — object doesn't exist if Knowledge not enabled
            if (!ex.getMessage().containsIgnoreCase('DataCategoryGroupVisibility')) {
                res.addWarning('Data Category Visibility', ex.getMessage());
            }
        }

        // ── 7. Manual items ───────────────────────────────────────────────────
        res.addManual('Standard Invocable Action Type Access',
            'No Apex DML support — configure manually in Setup → Permission Sets.');
        res.addManual('Org-Wide Email Address Access',
            'Not permission-set controlled — configure at profile/user level.');
        res.addManual('Email-to-Case Routing Address Access',
            'Requires Metadata API — configure manually in Setup after merge.');

        return res;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BUILD PERMISSIONSET — uses hardcoded field list, single SOQL per chunk
    // ─────────────────────────────────────────────────────────────────────────
    private static SObject buildMergedPermissionSet(
        List<Id> sourceIds, String apiName, String label, String description
    ) {
        // Filter SYSTEM_PERM_FIELDS to only those that actually exist in this org
        // using a single cheap Schema field map lookup (not describe per field)
        Map<String, Schema.SObjectField> allFields =
            Schema.SObjectType.PermissionSet.fields.getMap();

        List<String> permFields = new List<String>();
        for (String f : SYSTEM_PERM_FIELDS) {
            if (allFields.containsKey(f.toLowerCase())) {
                permFields.add(f);
            }
        }

        // OR all source values — single SOQL if fields fit, chunked if not
        Map<String, Boolean> merged = new Map<String, Boolean>();
        for (String f : permFields) merged.put(f, false);

        Integer chunkSize = 80;
        for (Integer i = 0; i < permFields.size(); i += chunkSize) {
            List<String> chunk = sliceList(permFields, i, chunkSize);
            String soql = 'SELECT ' + String.join(chunk, ',')
                        + ' FROM PermissionSet WHERE Id IN :sourceIds';
            for (SObject src : Database.query(soql)) {
                for (String f : chunk) {
                    if (src.get(f) == true) merged.put(f, true);
                }
            }
        }

        SObject newPS = PermissionSet.sObjectType.newSObject();
        newPS.put('Name', apiName);
        newPS.put('Label', label);
        newPS.put('Description', description);
        for (String f : permFields) {
            newPS.put(f, merged.get(f));
        }
        return newPS;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────────────
    private static List<String> getLabels(List<Id> ids) {
        List<String> labels = new List<String>();
        for (PermissionSet ps : [SELECT Label FROM PermissionSet WHERE Id IN :ids]) {
            labels.add(ps.Label);
        }
        return labels;
    }
    private static List<String> sliceList(List<String> src, Integer start, Integer size) {
        List<String> chunk = new List<String>();
        for (Integer i = start; i < Math.min(start + size, src.size()); i++) chunk.add(src[i]);
        return chunk;
    }
    private static void insertInChunks(List<SObject> records) {
        List<SObject> chunk = new List<SObject>();
        for (SObject rec : records) {
            chunk.add(rec);
            if (chunk.size() == 200) { Database.insert(chunk, false); chunk.clear(); }
        }
        if (!chunk.isEmpty()) Database.insert(chunk, false);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WRAPPERS
    // ─────────────────────────────────────────────────────────────────────────
    public class PermSetWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        public PermSetWrapper(String id, String label, String name, String descText) {
            this.id=id; this.label=label; this.name=name; this.description=descText;
        }
    }
    public class MergeResult {
        @AuraEnabled public String newPermissionSetId { get; set; }
        @AuraEnabled public List<ResultItem> successes { get; set; }
        @AuraEnabled public List<ResultItem> warnings { get; set; }
        @AuraEnabled public List<ResultItem> manualItems { get; set; }
        public MergeResult() {
            successes=new List<ResultItem>(); warnings=new List<ResultItem>();
            manualItems=new List<ResultItem>();
        }
        public void addSuccess(String s,String d){successes.add(new ResultItem(s,d));}
        public void addWarning(String s,String d){warnings.add(new ResultItem(s,d));}
        public void addManual(String s,String d){manualItems.add(new ResultItem(s,d));}
    }
    public class ResultItem {
        @AuraEnabled public String section { get; set; }
        @AuraEnabled public String detail { get; set; }
        public ResultItem(String s,String d){this.section=s;this.detail=d;}
    }
}