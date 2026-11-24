/** MCP tool: delete an MCP Demo record (moves it to the Recycle Bin). */
global with sharing class McpDemoDelete {
    global class Request {
        @InvocableVariable(required=true label='Record Id' description='Id of the MCP Demo record to delete. Confirm with the user before deleting.')
        global String recordId;
    }

    global class Result {
        @InvocableVariable(label='Success' description='True if the record was deleted.')
        global Boolean success;
        @InvocableVariable(label='Message' description='What happened, or why the delete failed.')
        global String message;
        @InvocableVariable(label='Record Id' description='Id of the record the call acted on.')
        global String recordId;
    }

    @InvocableMethod(
        label='Delete MCP Demo Record'
        description='Deletes an MCP Demo record by recordId. The record goes to the Recycle Bin and can be restored there for 15 days. Confirm with the user before calling.'
        category='MCP Tools'
    )
    global static List<Result> deleteRecords(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        List<Id> toDelete = new List<Id>();
        List<Integer> deleteIndex = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result res = new Result();
            res.success = false;
            res.recordId = req == null ? null : req.recordId;
            results.add(res);
            if (req == null || !McpDemoSupport.isValidId(req.recordId)) {
                res.message = 'A valid MCP Demo recordId is required.';
                continue;
            }
            toDelete.add(Id.valueOf(req.recordId));
            deleteIndex.add(i);
        }
        if (toDelete.isEmpty()) {
            return results;
        }
        List<Database.DeleteResult> deletes;
        try {
            deletes = Database.delete(toDelete, false, AccessLevel.USER_MODE);
        } catch (Exception e) {
            // USER_MODE raises (rather than returning row errors) when the caller lacks object access.
            for (Integer k : deleteIndex) {
                results[k].message = 'Delete failed: ' + e.getMessage();
            }
            return results;
        }
        for (Integer j = 0; j < deletes.size(); j++) {
            Result res = results[deleteIndex[j]];
            if (deletes[j].isSuccess()) {
                res.success = true;
                res.message = 'Deleted MCP Demo record ' + deletes[j].getId() + ' (in Recycle Bin for 15 days).';
            } else {
                res.message = 'Delete failed: ' + McpDemoSupport.errorText(deletes[j].getErrors());
            }
        }
        return results;
    }
}
