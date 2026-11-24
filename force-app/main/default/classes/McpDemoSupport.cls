/**
 * Shared helpers for the MCP Demo tools. All data access runs in USER_MODE so the
 * MCP caller's CRUD, FLS and sharing apply.
 */
public with sharing class McpDemoSupport {
    public static final Set<String> STATUSES = new Set<String>{ 'New', 'In Progress', 'Done' };

    public static Map<Id, MCP_Demo__c> loadByIds(Set<Id> ids) {
        if (ids.isEmpty()) {
            return new Map<Id, MCP_Demo__c>();
        }
        return new Map<Id, MCP_Demo__c>([
            SELECT Id, Name, Description__c, Status__c, Amount__c, Due_Date__c, LastModifiedDate
            FROM MCP_Demo__c
            WHERE Id IN :ids
            WITH USER_MODE
        ]);
    }

    /** Returns an error message, or null if the status is valid (blank is allowed). */
    public static String validateStatus(String status) {
        if (String.isBlank(status) || STATUSES.contains(status)) {
            return null;
        }
        return 'Invalid status "' + status + '". Use one of: New, In Progress, Done.';
    }

    public static String errorText(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error e : errors) {
            parts.add(e.getMessage());
        }
        return String.join(parts, ' ');
    }

    public static Boolean isValidId(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            return Id.valueOf(value).getSobjectType() == MCP_Demo__c.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }
}
