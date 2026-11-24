@IsTest
private class McpDemoToolsTest {

    /** A user set up like a real MCP caller: standard profile + the packaged MCP_Tool_User permission set. */
    private static User newUser(String alias, Boolean withToolAccess) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = alias, Email = alias + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = alias, LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles',
            Username = alias + '.' + System.currentTimeMillis() + '@example.com.mcptest'
        );
        insert u;
        if (withToolAccess) {
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'MCP_Tool_User' LIMIT 1].Id
            );
        }
        return u;
    }

    private static McpDemoCreate.Result createOne(String name, String status, Decimal amount) {
        McpDemoCreate.Request req = new McpDemoCreate.Request();
        req.name = name;
        req.status = status;
        req.amount = amount;
        req.description = 'Created by test';
        req.dueDate = Date.today().addDays(7);
        return McpDemoCreate.create(new List<McpDemoCreate.Request>{ req })[0];
    }

    private static Map<String, Object> firstRecord(McpDemoRead.Result res) {
        return (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(res.recordsJson))[0];
    }

    @IsTest
    static void outputsSerializeLikeTheActionsApi() {
        // The REST actions API and hosted MCP fail on nested Apex-defined outputs
        // ("Type cannot be serialized"). Apex's JSON.serialize is not that serializer,
        // so this guards the flat-output contract; verify real calls via
        // /services/data/vXX.0/actions/custom/apex/<ns>__<Class>.
        System.runAs(newUser('serializ', true)) {
            McpDemoCreate.Result created = createOne('Serialize Me', 'New', 7);
            JSON.serialize(created);
            McpDemoRead.Request rq = new McpDemoRead.Request();
            rq.recordId = created.recordId;
            McpDemoRead.Result read = McpDemoRead.read(new List<McpDemoRead.Request>{ rq })[0];
            JSON.serialize(read);
            Assert.isNull(read.records, 'Deprecated nested output must stay empty');
            Assert.areEqual('Serialize Me', firstRecord(read).get('name'));
            McpDemoUpdate.Request up = new McpDemoUpdate.Request();
            up.recordId = created.recordId;
            up.status = 'Done';
            McpDemoUpdate.Result updated = McpDemoUpdate.updateRecords(new List<McpDemoUpdate.Request>{ up })[0];
            JSON.serialize(updated);
            Assert.isNull(updated.record);
            Assert.areEqual('Done', updated.status);
        }
    }

    @IsTest
    static void fullCrudLifecycle() {
        System.runAs(newUser('fullcrud', true)) {
            // Create
            McpDemoCreate.Result created = createOne('Alpha Demo', null, 100.5);
            Assert.isTrue(created.success, created.message);
            Assert.areEqual('New', created.status, 'Status defaults to New');
            Id recId = created.recordId;

            // Read by Id
            McpDemoRead.Request readReq = new McpDemoRead.Request();
            readReq.recordId = recId;
            McpDemoRead.Result readRes = McpDemoRead.read(new List<McpDemoRead.Request>{ readReq })[0];
            Assert.isTrue(readRes.success, readRes.message);
            Assert.areEqual(1, readRes.recordCount);
            Assert.areEqual('Alpha Demo', firstRecord(readRes).get('name'));
            Assert.areEqual(100.5, (Decimal) firstRecord(readRes).get('amount'));

            // Update only status and amount
            McpDemoUpdate.Request upd = new McpDemoUpdate.Request();
            upd.recordId = recId;
            upd.status = 'Done';
            upd.amount = 250;
            McpDemoUpdate.Result updRes = McpDemoUpdate.updateRecords(new List<McpDemoUpdate.Request>{ upd })[0];
            Assert.isTrue(updRes.success, updRes.message);
            Assert.areEqual('Done', updRes.status);
            Assert.areEqual(250, updRes.amount);
            Assert.areEqual('Alpha Demo', updRes.name, 'Omitted fields stay unchanged');

            // Delete
            McpDemoDelete.Request del = new McpDemoDelete.Request();
            del.recordId = recId;
            McpDemoDelete.Result delRes = McpDemoDelete.deleteRecords(new List<McpDemoDelete.Request>{ del })[0];
            Assert.isTrue(delRes.success, delRes.message);
            Assert.areEqual(0, [SELECT COUNT() FROM MCP_Demo__c WHERE Id = :recId]);

            // Read after delete: success, zero rows
            readRes = McpDemoRead.read(new List<McpDemoRead.Request>{ readReq })[0];
            Assert.isTrue(readRes.success);
            Assert.areEqual(0, readRes.recordCount);
        }
    }

    @IsTest
    static void searchFiltersAndLimits() {
        System.runAs(newUser('searchfi', true)) {
            createOne('Project Apollo', 'In Progress', 1);
            createOne('Project Gemini', 'Done', 2);
            createOne('Other 50%_off', 'In Progress', 3);

            McpDemoRead.Request byName = new McpDemoRead.Request();
            byName.nameContains = 'project';
            Assert.areEqual(2, McpDemoRead.read(new List<McpDemoRead.Request>{ byName })[0].recordCount);

            McpDemoRead.Request byStatus = new McpDemoRead.Request();
            byStatus.status = 'In Progress';
            byStatus.maxRecords = 1;
            McpDemoRead.Result limited = McpDemoRead.read(new List<McpDemoRead.Request>{ byStatus })[0];
            Assert.areEqual(1, limited.recordCount);

            McpDemoRead.Request wildcard = new McpDemoRead.Request();
            wildcard.nameContains = '50%_';
            Assert.areEqual(1, McpDemoRead.read(new List<McpDemoRead.Request>{ wildcard })[0].recordCount,
                'LIKE wildcards in input are matched literally');

            McpDemoRead.Result all = McpDemoRead.read(new List<McpDemoRead.Request>{ null })[0];
            Assert.areEqual(3, all.recordCount);

            McpDemoRead.Request none = new McpDemoRead.Request();
            none.nameContains = 'zzz';
            McpDemoRead.Result empty = McpDemoRead.read(new List<McpDemoRead.Request>{ none })[0];
            Assert.isTrue(empty.success);
            Assert.areEqual('No matching MCP Demo records.', empty.message);
        }
    }

    @IsTest
    static void validationErrorsAreReturnedNotThrown() {
        System.runAs(newUser('validati', true)) {
            McpDemoCreate.Request noName = new McpDemoCreate.Request();
            McpDemoCreate.Request badStatus = new McpDemoCreate.Request();
            badStatus.name = 'X';
            badStatus.status = 'Archived';
            List<McpDemoCreate.Result> createRes =
                McpDemoCreate.create(new List<McpDemoCreate.Request>{ noName, badStatus, null });
            Assert.isFalse(createRes[0].success);
            Assert.isTrue(createRes[1].message.contains('Invalid status'));
            Assert.isFalse(createRes[2].success);

            McpDemoRead.Request badId = new McpDemoRead.Request();
            badId.recordId = '001000000000000AAA';
            Assert.isFalse(McpDemoRead.read(new List<McpDemoRead.Request>{ badId })[0].success);
            McpDemoRead.Request badReadStatus = new McpDemoRead.Request();
            badReadStatus.status = 'Nope';
            Assert.isFalse(McpDemoRead.read(new List<McpDemoRead.Request>{ badReadStatus })[0].success);

            Id recId = createOne('Keep', 'New', null).recordId;
            McpDemoUpdate.Request nothing = new McpDemoUpdate.Request();
            nothing.recordId = recId;
            McpDemoUpdate.Request updBadStatus = new McpDemoUpdate.Request();
            updBadStatus.recordId = recId;
            updBadStatus.status = 'Nope';
            McpDemoUpdate.Request updBadId = new McpDemoUpdate.Request();
            updBadId.recordId = 'not-an-id';
            List<McpDemoUpdate.Result> updRes = McpDemoUpdate.updateRecords(
                new List<McpDemoUpdate.Request>{ nothing, updBadStatus, updBadId });
            Assert.isTrue(updRes[0].message.startsWith('Nothing to update'));
            Assert.isTrue(updRes[1].message.contains('Invalid status'));
            Assert.isFalse(updRes[2].success);

            McpDemoDelete.Request delBad = new McpDemoDelete.Request();
            delBad.recordId = '';
            Assert.isFalse(McpDemoDelete.deleteRecords(new List<McpDemoDelete.Request>{ delBad })[0].success);

            Assert.areEqual(0, McpDemoCreate.create(null).size());
            Assert.areEqual(0, McpDemoRead.read(null).size());
            Assert.areEqual(0, McpDemoUpdate.updateRecords(null).size());
            Assert.areEqual(0, McpDemoDelete.deleteRecords(null).size());
        }
    }

    @IsTest
    static void userWithoutAccessGetsFailureMessages() {
        Id recId;
        System.runAs(newUser('mcpowner', true)) {
            recId = createOne('Owner Only', 'New', null).recordId;
        }
        User u = newUser('mcpnoacc', false);

        System.runAs(u) {
            Assert.isFalse(createOne('Blocked', 'New', null).success, 'No object access means create fails');

            McpDemoRead.Request readReq = new McpDemoRead.Request();
            readReq.recordId = recId;
            Assert.isFalse(McpDemoRead.read(new List<McpDemoRead.Request>{ readReq })[0].success);

            McpDemoUpdate.Request upd = new McpDemoUpdate.Request();
            upd.recordId = recId;
            upd.status = 'Done';
            Assert.isFalse(McpDemoUpdate.updateRecords(new List<McpDemoUpdate.Request>{ upd })[0].success);

            McpDemoDelete.Request del = new McpDemoDelete.Request();
            del.recordId = recId;
            Assert.isFalse(McpDemoDelete.deleteRecords(new List<McpDemoDelete.Request>{ del })[0].success);
        }
    }
}
