/** MCP tool: create an MCP Demo record. */
global with sharing class McpDemoCreate {
    global class Request {
        @InvocableVariable(required=true label='Name' description='Name of the new MCP Demo record.')
        global String name;
        @InvocableVariable(label='Description' description='Optional free-text description.')
        global String description;
        @InvocableVariable(label='Status' description='Optional. One of: New, In Progress, Done. Defaults to New.')
        global String status;
        @InvocableVariable(label='Amount' description='Optional numeric amount, up to 2 decimal places.')
        global Decimal amount;
        @InvocableVariable(label='Due Date' description='Optional due date, YYYY-MM-DD.')
        global Date dueDate;
    }

    global class Result {
        @InvocableVariable(label='Success' description='True if the record was created.')
        global Boolean success;
        @InvocableVariable(label='Message' description='What happened, or why it failed.')
        global String message;
        @InvocableVariable(label='Record' description='Deprecated: always empty. Use the recordId, name, description, status, amount and dueDate outputs.')
        global McpDemoRecord record;
        @InvocableVariable(label='Record Id' description='Salesforce Id of the MCP Demo record. Use it for read, update and delete calls.')
        global String recordId;
        @InvocableVariable(label='Name' description='Name of the record.')
        global String name;
        @InvocableVariable(label='Description' description='Free-text description.')
        global String description;
        @InvocableVariable(label='Status' description='One of: New, In Progress, Done.')
        global String status;
        @InvocableVariable(label='Amount' description='Numeric amount.')
        global Decimal amount;
        @InvocableVariable(label='Due Date' description='Due date, YYYY-MM-DD.')
        global Date dueDate;
    }

    @InvocableMethod(
        label='Create MCP Demo Record'
        description='Creates a new MCP Demo record. Requires a name; description, status (New, In Progress, Done), amount and due date are optional. Returns the new record with its recordId.'
        category='MCP Tools'
    )
    global static List<Result> create(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        List<MCP_Demo__c> toInsert = new List<MCP_Demo__c>();
        List<Integer> insertIndex = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = new Result();
            res.success = false;
            results.add(res);
            if (req == null || String.isBlank(req.name)) {
                res.message = 'A name is required to create an MCP Demo record.';
                continue;
            }
            String statusError = McpDemoSupport.validateStatus(req.status);
            if (statusError != null) {
                res.message = statusError;
                continue;
            }
            toInsert.add(new MCP_Demo__c(
                Name = req.name.trim(),
                Description__c = req.description,
                Status__c = String.isBlank(req.status) ? 'New' : req.status,
                Amount__c = req.amount,
                Due_Date__c = req.dueDate
            ));
            insertIndex.add(i);
        }
        if (toInsert.isEmpty()) {
            return results;
        }
        List<Database.SaveResult> saves;
        try {
            saves = Database.insert(toInsert, false, AccessLevel.USER_MODE);
        } catch (Exception e) {
            // USER_MODE raises (rather than returning row errors) when the caller lacks object access.
            for (Integer k : insertIndex) {
                results[k].message = 'Create failed: ' + e.getMessage();
            }
            return results;
        }
        Set<Id> created = new Set<Id>();
        for (Database.SaveResult sr : saves) {
            if (sr.isSuccess()) {
                created.add(sr.getId());
            }
        }
        Map<Id, MCP_Demo__c> reloaded = McpDemoSupport.loadByIds(created);
        for (Integer j = 0; j < saves.size(); j++) {
            Result res = results[insertIndex[j]];
            if (saves[j].isSuccess()) {
                res.success = true;
                res.message = 'Created MCP Demo record ' + saves[j].getId() + '.';
                MCP_Demo__c rec = reloaded.get(saves[j].getId());
                res.recordId = rec.Id;
                res.name = rec.Name;
                res.description = rec.Description__c;
                res.status = rec.Status__c;
                res.amount = rec.Amount__c;
                res.dueDate = rec.Due_Date__c;
            } else {
                res.message = 'Create failed: ' + McpDemoSupport.errorText(saves[j].getErrors());
            }
        }
        return results;
    }
}
