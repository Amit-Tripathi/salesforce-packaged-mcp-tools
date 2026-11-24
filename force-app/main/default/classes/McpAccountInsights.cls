/**
 * MCP-ready Apex action: account health snapshot.
 *
 * Exposed to AI agents through a Salesforce Hosted MCP Server. After the
 * package is installed, a subscriber admin adds this action as a tool in
 * Setup > Integrations > Salesforce MCP Servers.
 *
 * Requirements for MCP tool discovery:
 *  - the class and method are global
 *  - the method is annotated with @InvocableMethod
 *  - every @InvocableVariable has a description (it becomes the tool's JSON schema docs)
 *
 * All queries run WITH USER_MODE, so the MCP caller's sharing, CRUD and FLS apply.
 */
global with sharing class McpAccountInsights {

    @TestVisible
    private static final Integer MAX_ROWS = 10;

    global class Request {
        @InvocableVariable(
            required=true
            label='Account Name'
            description='Name of the Account to analyze. Partial names are accepted: an exact match is tried first, then a contains-match.'
        )
        global String accountName;
    }

    global class Result {
        @InvocableVariable(label='Account Found' description='True if a matching account was found. If false, ask the user to clarify the account name.')
        global Boolean accountFound;

        @InvocableVariable(label='Match Type' description='How the account was matched: exact, partial, or none.')
        global String matchType;

        @InvocableVariable(label='Account Id' description='Salesforce Id of the matched account.')
        global Id accountId;

        @InvocableVariable(label='Account Name' description='Name of the matched account.')
        global String accountName;

        @InvocableVariable(label='Industry' description='Industry of the matched account, if set.')
        global String industry;

        @InvocableVariable(label='Open Opportunity Count' description='Number of open (not closed) opportunities on the account.')
        global Integer openOpportunityCount;

        @InvocableVariable(label='Open Pipeline Amount' description='Sum of Amount across open opportunities, in the org currency.')
        global Decimal openPipelineAmount;

        @InvocableVariable(label='Weighted Pipeline Amount' description='Open pipeline weighted by each opportunity Probability: the realistic expected revenue.')
        global Decimal weightedPipelineAmount;

        @InvocableVariable(label='Open Case Count' description='Number of open (not closed) support cases on the account.')
        global Integer openCaseCount;

        @InvocableVariable(label='High Priority Case Count' description='Number of open cases with Priority = High.')
        global Integer highPriorityCaseCount;

        @InvocableVariable(label='Health' description='Overall account health: Healthy, Watch, At Risk, or No Activity.')
        global String health;

        @InvocableVariable(label='Summary' description='One-paragraph plain-language summary of pipeline and support status, including the top open deals.')
        global String summary;
    }

    @InvocableMethod(
        label='Get Account Insights'
        description='Returns a health snapshot for an account given its name: open pipeline (total and probability-weighted), top open deals, open and high-priority support cases, and an overall health rating. Supports partial account names.'
        category='MCP Tools'
    )
    global static List<Result> getAccountInsights(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null) {
            return results;
        }
        Map<Integer, Account> accountByIndex = resolveAccounts(requests);

        Set<Id> accountIds = new Set<Id>();
        for (Account acc : accountByIndex.values()) {
            accountIds.add(acc.Id);
        }
        Map<Id, List<Opportunity>> oppsByAccount = loadOpportunities(accountIds);
        Map<Id, List<Case>> casesByAccount = loadCases(accountIds);

        for (Integer i = 0; i < requests.size(); i++) {
            Account acc = accountByIndex.get(i);
            if (acc == null) {
                results.add(notFound(requests[i] == null ? null : requests[i].accountName));
                continue;
            }
            Request req = requests[i];
            Result res = buildResult(
                acc,
                acc.Name.equalsIgnoreCase(req.accountName.trim()) ? 'exact' : 'partial',
                oppsByAccount.get(acc.Id),
                casesByAccount.get(acc.Id)
            );
            results.add(res);
        }
        return results;
    }

    // Exact names in one query; per-request contains-match only for names with no exact hit.
    private static Map<Integer, Account> resolveAccounts(List<Request> requests) {
        Set<String> names = new Set<String>();
        for (Request req : requests) {
            if (req != null && String.isNotBlank(req.accountName)) {
                names.add(req.accountName.trim());
            }
        }
        Map<String, Account> exactByLowerName = new Map<String, Account>();
        if (!names.isEmpty()) {
            for (Account acc : [
                SELECT Id, Name, Industry
                FROM Account
                WHERE Name IN :names
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
            ]) {
                String key = acc.Name.toLowerCase();
                if (!exactByLowerName.containsKey(key)) {
                    exactByLowerName.put(key, acc);
                }
            }
        }

        Map<Integer, Account> byIndex = new Map<Integer, Account>();
        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            if (req == null || String.isBlank(req.accountName)) {
                continue;
            }
            String name = req.accountName.trim();
            Account acc = exactByLowerName.get(name.toLowerCase());
            if (acc == null && Limits.getQueries() < Limits.getLimitQueries() - 5) {
                String pattern = '%' + name.replace('%', '\\%').replace('_', '\\_') + '%';
                List<Account> partial = [
                    SELECT Id, Name, Industry
                    FROM Account
                    WHERE Name LIKE :pattern
                    WITH USER_MODE
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];
                acc = partial.isEmpty() ? null : partial[0];
            }
            if (acc != null) {
                byIndex.put(i, acc);
            }
        }
        return byIndex;
    }

    private static Map<Id, List<Opportunity>> loadOpportunities(Set<Id> accountIds) {
        Map<Id, List<Opportunity>> result = new Map<Id, List<Opportunity>>();
        if (accountIds.isEmpty()) {
            return result;
        }
        for (Opportunity opp : [
            SELECT Id, Name, AccountId, Amount, Probability, StageName, CloseDate
            FROM Opportunity
            WHERE AccountId IN :accountIds AND IsClosed = false
            WITH USER_MODE
            ORDER BY Amount DESC NULLS LAST
        ]) {
            if (!result.containsKey(opp.AccountId)) {
                result.put(opp.AccountId, new List<Opportunity>());
            }
            result.get(opp.AccountId).add(opp);
        }
        return result;
    }

    private static Map<Id, List<Case>> loadCases(Set<Id> accountIds) {
        Map<Id, List<Case>> result = new Map<Id, List<Case>>();
        if (accountIds.isEmpty()) {
            return result;
        }
        for (Case c : [
            SELECT Id, AccountId, Priority
            FROM Case
            WHERE AccountId IN :accountIds AND IsClosed = false
            WITH USER_MODE
        ]) {
            if (!result.containsKey(c.AccountId)) {
                result.put(c.AccountId, new List<Case>());
            }
            result.get(c.AccountId).add(c);
        }
        return result;
    }

    private static Result buildResult(Account acc, String matchType, List<Opportunity> opps, List<Case> cases) {
        opps = opps == null ? new List<Opportunity>() : opps;
        cases = cases == null ? new List<Case>() : cases;

        Decimal total = 0;
        Decimal weighted = 0;
        for (Opportunity opp : opps) {
            Decimal amount = opp.Amount == null ? 0 : opp.Amount;
            Decimal probability = opp.Probability == null ? 0 : opp.Probability;
            total += amount;
            weighted += amount * probability / 100;
        }
        Integer highPriority = 0;
        for (Case c : cases) {
            if (c.Priority == 'High') {
                highPriority++;
            }
        }

        Result res = new Result();
        res.accountFound = true;
        res.matchType = matchType;
        res.accountId = acc.Id;
        res.accountName = acc.Name;
        res.industry = acc.Industry;
        res.openOpportunityCount = opps.size();
        res.openPipelineAmount = total.setScale(2);
        res.weightedPipelineAmount = weighted.setScale(2);
        res.openCaseCount = cases.size();
        res.highPriorityCaseCount = highPriority;
        res.health = assessHealth(opps.size(), total, weighted, cases.size(), highPriority);
        res.summary = summarize(res, opps);
        return res;
    }

    @TestVisible
    private static String assessHealth(Integer oppCount, Decimal total, Decimal weighted, Integer caseCount, Integer highPriority) {
        if (oppCount == 0 && caseCount == 0) {
            return 'No Activity';
        }
        Decimal conversion = total > 0 ? weighted / total : 0;
        if (highPriority >= 3 || (oppCount > 0 && conversion < 0.3)) {
            return 'At Risk';
        }
        if (highPriority > 0 || (oppCount > 0 && conversion < 0.5)) {
            return 'Watch';
        }
        return 'Healthy';
    }

    private static String summarize(Result res, List<Opportunity> opps) {
        List<String> parts = new List<String>();
        parts.add(res.accountName + ' (' + res.matchType + ' match) is rated ' + res.health + '.');
        parts.add(
            res.openOpportunityCount + ' open opportunities worth ' + res.openPipelineAmount.format() +
            ' (' + res.weightedPipelineAmount.format() + ' weighted).'
        );
        parts.add(res.openCaseCount + ' open cases, ' + res.highPriorityCaseCount + ' high priority.');
        if (!opps.isEmpty()) {
            List<String> top = new List<String>();
            for (Integer i = 0; i < Math.min(opps.size(), 3); i++) {
                Opportunity opp = opps[i];
                top.add(
                    opp.Name + ' [' + opp.StageName + ', ' +
                    (opp.Amount == null ? 'no amount' : opp.Amount.format()) +
                    ', closes ' + String.valueOf(opp.CloseDate) + ']'
                );
            }
            parts.add('Top open deals: ' + String.join(top, '; ') + '.');
        }
        return String.join(parts, ' ');
    }

    private static Result notFound(String name) {
        Result res = new Result();
        res.accountFound = false;
        res.matchType = 'none';
        res.health = 'No Activity';
        res.summary = String.isBlank(name)
            ? 'No account name was provided.'
            : 'No account found matching "' + name + '". Ask the user for the exact account name.';
        return res;
    }
}
