/** MCP tool: read or search MCP Demo records. */
global with sharing class McpDemoRead {
    @TestVisible
    private static final Integer DEFAULT_LIMIT = 10;
    @TestVisible
    private static final Integer MAX_LIMIT = 50;

    global class Request {
        @InvocableVariable(label='Record Id' description='Optional. Return just this record. When set, the other filters are ignored.')
        global String recordId;
        @InvocableVariable(label='Name Contains' description='Optional. Return records whose name contains this text (case-insensitive).')
        global String nameContains;
        @InvocableVariable(label='Status' description='Optional. Filter by status: New, In Progress, or Done.')
        global String status;
        @InvocableVariable(label='Max Records' description='Optional. Maximum records to return, 1 to 50. Defaults to 10. Newest-modified first.')
        global Integer maxRecords;
    }

    global class Result {
        @InvocableVariable(label='Success' description='True if the search ran. A search with zero matches is still a success.')
        global Boolean success;
        @InvocableVariable(label='Message' description='Summary of what was found, or why the call failed.')
        global String message;
        @InvocableVariable(label='Record Count' description='Number of records returned.')
        global Integer recordCount;
        @InvocableVariable(label='Records' description='Deprecated: always empty. Use recordsJson.')
        global List<McpDemoRecord> records;
        @InvocableVariable(label='Records JSON' description='Matching records as a JSON array, newest-modified first. Each item has recordId, name, description, status, amount, dueDate (YYYY-MM-DD) and lastModifiedDate.')
        global String recordsJson;
    }

    @InvocableMethod(
        label='Read MCP Demo Records'
        description='Reads MCP Demo records. Pass recordId to fetch one record, or filter by nameContains and/or status to search. With no filters, returns the most recently modified records. Returns up to maxRecords (default 10, max 50) in recordsJson, a JSON array.'
        category='MCP Tools'
    )
    global static List<Result> read(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        for (Request req : requests) {
            results.add(readOne(req == null ? new Request() : req));
        }
        return results;
    }

    private static Result readOne(Request req) {
        Result res = new Result();
        res.success = false;
        res.recordCount = 0;
        List<McpDemoRecord> found = new List<McpDemoRecord>();
        res.recordsJson = '[]';

        if (String.isNotBlank(req.recordId) && !McpDemoSupport.isValidId(req.recordId)) {
            res.message = 'recordId "' + req.recordId + '" is not a valid MCP Demo record Id.';
            return res;
        }
        String statusError = McpDemoSupport.validateStatus(req.status);
        if (statusError != null) {
            res.message = statusError;
            return res;
        }
        if (Limits.getQueries() >= Limits.getLimitQueries() - 1) {
            res.message = 'Too many requests in one call; retry with fewer.';
            return res;
        }

        Integer lim = req.maxRecords == null ? DEFAULT_LIMIT : Math.max(1, Math.min(req.maxRecords, MAX_LIMIT));
        Map<String, Object> binds = new Map<String, Object>{ 'lim' => lim };
        List<String> filters = new List<String>();
        if (String.isNotBlank(req.recordId)) {
            filters.add('Id = :recordId');
            binds.put('recordId', Id.valueOf(req.recordId));
        } else {
            if (String.isNotBlank(req.nameContains)) {
                filters.add('Name LIKE :namePattern');
                binds.put('namePattern', '%' + req.nameContains.trim().replace('%', '\\%').replace('_', '\\_') + '%');
            }
            if (String.isNotBlank(req.status)) {
                filters.add('Status__c = :status');
                binds.put('status', req.status);
            }
        }
        String soql =
            'SELECT Id, Name, Description__c, Status__c, Amount__c, Due_Date__c, LastModifiedDate FROM MCP_Demo__c' +
            (filters.isEmpty() ? '' : ' WHERE ' + String.join(filters, ' AND ')) +
            ' ORDER BY LastModifiedDate DESC LIMIT :lim';

        try {
            for (MCP_Demo__c rec : (List<MCP_Demo__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
                found.add(new McpDemoRecord(rec));
            }
        } catch (Exception e) {
            res.message = 'Read failed: ' + e.getMessage();
            return res;
        }
        res.success = true;
        res.recordCount = found.size();
        res.recordsJson = JSON.serialize(found);
        res.message = res.recordCount == 0
            ? (String.isNotBlank(req.recordId) ? 'No MCP Demo record found with Id ' + req.recordId + ', or you lack access to it.' : 'No matching MCP Demo records.')
            : 'Found ' + res.recordCount + ' MCP Demo record(s).';
        return res;
    }
}
