/**
 * Agent-facing shape of an MCP Demo record. Returned by the MCP Demo tools so agents
 * see stable, documented fields instead of raw SObjects.
 */
global class McpDemoRecord {
    @InvocableVariable(label='Record Id' description='Salesforce Id of the MCP Demo record. Use it for read, update and delete calls.')
    global Id recordId;

    @InvocableVariable(label='Name' description='Name of the MCP Demo record.')
    global String name;

    @InvocableVariable(label='Description' description='Free-text description.')
    global String description;

    @InvocableVariable(label='Status' description='One of: New, In Progress, Done.')
    global String status;

    @InvocableVariable(label='Amount' description='Numeric amount with up to 2 decimal places.')
    global Decimal amount;

    @InvocableVariable(label='Due Date' description='Due date in YYYY-MM-DD format.')
    global Date dueDate;

    @InvocableVariable(label='Last Modified' description='When the record was last changed (UTC).')
    global Datetime lastModifiedDate;

    global McpDemoRecord() {}

    public McpDemoRecord(MCP_Demo__c rec) {
        recordId = rec.Id;
        name = rec.Name;
        description = rec.Description__c;
        status = rec.Status__c;
        amount = rec.Amount__c;
        dueDate = rec.Due_Date__c;
        lastModifiedDate = rec.LastModifiedDate;
    }
}
