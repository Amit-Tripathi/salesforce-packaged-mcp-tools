@IsTest
private class McpAccountInsightsTest {

    @TestSetup
    static void setup() {
        Account acme = new Account(Name = 'Acme Corporation', Industry = 'Manufacturing');
        Account quiet = new Account(Name = 'Quiet Holdings');
        insert new List<Account>{ acme, quiet };

        insert new List<Opportunity>{
            new Opportunity(AccountId = acme.Id, Name = 'Acme Big Deal', StageName = 'Prospecting',
                CloseDate = Date.today().addDays(20), Amount = 100000, Probability = 90),
            new Opportunity(AccountId = acme.Id, Name = 'Acme Add-on', StageName = 'Prospecting',
                CloseDate = Date.today().addDays(60), Amount = 20000, Probability = 80),
            new Opportunity(AccountId = acme.Id, Name = 'Acme Lost', StageName = 'Closed Lost',
                CloseDate = Date.today().addDays(-5), Amount = 50000)
        };
        insert new Case(AccountId = acme.Id, Subject = 'Login issue', Priority = 'High', Status = 'New');
    }

    private static McpAccountInsights.Request req(String name) {
        McpAccountInsights.Request r = new McpAccountInsights.Request();
        r.accountName = name;
        return r;
    }

    @IsTest
    static void exactMatchReturnsPipelineAndCases() {
        Test.startTest();
        List<McpAccountInsights.Result> results =
            McpAccountInsights.getAccountInsights(new List<McpAccountInsights.Request>{ req('Acme Corporation') });
        Test.stopTest();

        McpAccountInsights.Result r = results[0];
        Assert.isTrue(r.accountFound);
        Assert.areEqual('exact', r.matchType);
        Assert.areEqual(2, r.openOpportunityCount, 'Closed opportunities must be excluded');
        Assert.areEqual(120000, r.openPipelineAmount);
        Assert.areEqual(1, r.openCaseCount);
        Assert.areEqual(1, r.highPriorityCaseCount);
        Assert.areEqual('Watch', r.health);
        Assert.isTrue(r.summary.contains('Acme Big Deal'));
    }

    @IsTest
    static void partialMatchAndNotFoundAndBlank() {
        List<McpAccountInsights.Result> results = McpAccountInsights.getAccountInsights(
            new List<McpAccountInsights.Request>{ req('acme'), req('Does Not Exist'), req(' '), null }
        );
        Assert.areEqual(4, results.size());
        Assert.areEqual('partial', results[0].matchType);
        Assert.isFalse(results[1].accountFound);
        Assert.isTrue(results[1].summary.contains('Does Not Exist'));
        Assert.isFalse(results[2].accountFound);
        Assert.isFalse(results[3].accountFound);
    }

    @IsTest
    static void accountWithNoActivity() {
        McpAccountInsights.Result r = McpAccountInsights.getAccountInsights(
            new List<McpAccountInsights.Request>{ req('Quiet Holdings') })[0];
        Assert.areEqual('No Activity', r.health);
        Assert.areEqual(0, r.openOpportunityCount);
    }

    @IsTest
    static void nullInputReturnsEmptyList() {
        Assert.areEqual(0, McpAccountInsights.getAccountInsights(null).size());
    }

    @IsTest
    static void healthRules() {
        Assert.areEqual('No Activity', McpAccountInsights.assessHealth(0, 0, 0, 0, 0));
        Assert.areEqual('At Risk', McpAccountInsights.assessHealth(1, 100, 10, 0, 0));
        Assert.areEqual('At Risk', McpAccountInsights.assessHealth(0, 0, 0, 3, 3));
        Assert.areEqual('Watch', McpAccountInsights.assessHealth(1, 100, 40, 0, 0));
        Assert.areEqual('Healthy', McpAccountInsights.assessHealth(1, 100, 80, 1, 0));
    }
}
