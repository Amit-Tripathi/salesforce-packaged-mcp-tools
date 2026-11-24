/** MCP tool: update fields on an existing MCP Demo record. */
global with sharing class McpDemoUpdate {
    global class Request {
        @InvocableVariable(required=true label='Record Id' description='Id of the MCP Demo record to update. Get it from the read or create tool.')
        global String recordId;
        @InvocableVariable(label='Name' description='Optional new name. Omit to leave unchanged.')
        global String name;
        @InvocableVariable(label='Description' description='Optional new description. Omit to leave unchanged.')
        global String description;
        @InvocableVariable(label='Status' description='Optional new status: New, In Progress, or Done. Omit to leave unchanged.')
        global String status;
        @InvocableVariable(label='Amount' description='Optional new amount. Omit to leave unchanged.')
        global Decimal amount;
        @InvocableVariable(label='Due Date' description='Optional new due date, YYYY-MM-DD. Omit to leave unchanged.')
        global Date dueDate;
    }

    global class Result {
        @InvocableVariable(label='Success' description='True if the record was updated.')
        global Boolean success;
        @InvocableVariable(label='Message' description='What changed, or why the update failed.')
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
        label='Update MCP Demo Record'
        description='Updates an existing MCP Demo record by recordId. Only the fields you pass (name, description, status, amount, dueDate) are changed; omitted fields keep their current values. Returns the updated record.'
        category='MCP Tools'
    )
    global static List<Result> updateRecords(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        List<MCP_Demo__c> toUpdate = new List<MCP_Demo__c>();
        List<Integer> updateIndex = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = new Result();
            res.success = false;
            results.add(res);
            if (req == null || !McpDemoSupport.isValidId(req.recordId)) {
                res.message = 'A valid MCP Demo recordId is required.';
                continue;
            }
            String statusError = McpDemoSupport.validateStatus(req.status);
            if (statusError != null) {
                res.message = statusError;
                continue;
            }
            MCP_Demo__c rec = new MCP_Demo__c(Id = req.recordId);
            List<String> changed = new List<String>();
            if (String.isNotBlank(req.name)) { rec.Name = req.name.trim(); changed.add('name'); }
            if (req.description != null) { rec.Description__c = req.description; changed.add('description'); }
            if (String.isNotBlank(req.status)) { rec.Status__c = req.status; changed.add('status'); }
            if (req.amount != null) { rec.Amount__c = req.amount; changed.add('amount'); }
            if (req.dueDate != null) { rec.Due_Date__c = req.dueDate; changed.add('dueDate'); }
            if (changed.isEmpty()) {
                res.message = 'Nothing to update: pass at least one of name, description, status, amount, dueDate.';
                continue;
            }
            res.message = String.join(changed, ', ');
            toUpdate.add(rec);
            updateIndex.add(i);
        }
        if (toUpdate.isEmpty()) {
            return results;
        }
        List<Database.SaveResult> saves;
        try {
            saves = Database.update(toUpdate, false, AccessLevel.USER_MODE);
        } catch (Exception e) {
            // USER_MODE raises (rather than returning row errors) when the caller lacks object access.
            for (Integer k : updateIndex) {
                results[k].message = 'Update failed: ' + e.getMessage();
            }
            return results;
        }
        Set<Id> updated = new Set<Id>();
        for (Database.SaveResult sr : saves) {
            if (sr.isSuccess()) {
                updated.add(sr.getId());
            }
        }
        Map<Id, MCP_Demo__c> reloaded = McpDemoSupport.loadByIds(updated);
        for (Integer j = 0; j < saves.size(); j++) {
            Result res = results[updateIndex[j]];
            if (saves[j].isSuccess()) {
                res.success = true;
                res.message = 'Updated ' + res.message + ' on MCP Demo record ' + saves[j].getId() + '.';
                MCP_Demo__c rec = reloaded.get(saves[j].getId());
                res.recordId = rec.Id;
                res.name = rec.Name;
                res.description = rec.Description__c;
                res.status = rec.Status__c;
                res.amount = rec.Amount__c;
                res.dueDate = rec.Due_Date__c;
            } else {
                res.message = 'Update failed: ' + McpDemoSupport.errorText(saves[j].getErrors());
            }
        }
        return results;
    }
}
