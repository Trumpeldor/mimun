@IsTest
private class SalesSummaryControllerTest {
    private static final String REP_A = 'rep.a';
    private static final String REP_B = 'rep.b';
    private static final String MANAGER = 'manager';

    @TestSetup
    static void setup() {
        // Users + permission set assignments are setup objects: create them in their own
        // runAs block to avoid MIXED_DML_OPERATION with the Accounts / Sales below.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User repA = newUser(REP_A);
            User repB = newUser(REP_B);
            User manager = newUser(MANAGER);
            insert new List<User>{ repA, repB, manager };

            Id repPermSet = permissionSetId('Sales_Summary_Sales_Rep');
            Id managerPermSet = permissionSetId('Sales_Summary_Sales_Manager');
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = repA.Id, PermissionSetId = repPermSet),
                new PermissionSetAssignment(AssigneeId = repB.Id, PermissionSetId = repPermSet),
                new PermissionSetAssignment(AssigneeId = manager.Id, PermissionSetId = managerPermSet)
            };
        }
    }

    // ---------------------------------------------------------------- happy path

    @IsTest
    static void defaultsToRunningUserAndReturnsTwelveMonths() {
        User repA = user(REP_A);
        Account acc = newAccount('Acme', repA.Id);
        Date thisMonth = Date.today().toStartOfMonth();
        insert new List<Sale__c>{
            newSale(acc.Id, thisMonth, 1500),
            newSale(acc.Id, thisMonth, 500),
            newSale(acc.Id, thisMonth.addMonths(-11), 2500)
        };

        SalesSummaryController.Summary summary;
        Test.startTest();
        System.runAs(repA) {
            summary = SalesSummaryController.getMonthlySummary(null);
        }
        Test.stopTest();

        Assert.areEqual(repA.Id, summary.salespersonId, 'null id should default to the running user');
        Assert.areEqual(12, summary.months.size(), 'always 12 months');
        Assert.isTrue(summary.hasSales);
        Assert.areEqual(3, summary.saleCount);
        Assert.areEqual(4500, summary.total);
        Assert.isFalse(summary.canViewAnySalesperson, 'a rep is not a manager');

        SalesSummaryController.MonthSummary oldest = summary.months[0];
        SalesSummaryController.MonthSummary current = summary.months[11];
        Assert.areEqual(thisMonth.addMonths(-11).month(), oldest.month, 'oldest month first');
        Assert.areEqual(2500, oldest.total);
        Assert.areEqual(thisMonth.month(), current.month, 'current month last');
        Assert.areEqual(thisMonth.year(), current.year);
        Assert.areEqual(2000, current.total);
        Assert.areEqual(2, current.saleCount);
    }

    @IsTest
    static void noSalesReturnsEmptySummary() {
        User repA = user(REP_A);
        newAccount('No Sales Ltd', repA.Id);

        SalesSummaryController.Summary summary;
        System.runAs(repA) {
            summary = SalesSummaryController.getMonthlySummary(repA.Id);
        }

        Assert.isFalse(summary.hasSales, 'the UI shows a toast instead of the table');
        Assert.areEqual(0, summary.total);
        Assert.areEqual(12, summary.months.size());
        for (SalesSummaryController.MonthSummary month : summary.months) {
            Assert.areEqual(0, month.total);
            Assert.isFalse(month.isLowSales, 'a month without sales is never flagged');
        }
    }

    // ---------------------------------------------------------------- business rules

    @IsTest
    static void saleBelongsToCurrentAccountOwner() {
        User repA = user(REP_A);
        User repB = user(REP_B);
        Account acc = newAccount('Moved Account', repB.Id);
        insert newSale(acc.Id, Date.today(), 3000);

        // The customer moves from rep B to rep A: its past sales move with it.
        acc.OwnerId = repA.Id;
        update acc;

        System.runAs(user(MANAGER)) {
            Assert.areEqual(3000, SalesSummaryController.getMonthlySummary(repA.Id).total, 'new owner gets the sales');
            Assert.areEqual(0, SalesSummaryController.getMonthlySummary(repB.Id).total, 'previous owner no longer does');
        }
    }

    @IsTest
    static void onlyLastTwelveCalendarMonthsAreIncluded() {
        User repA = user(REP_A);
        Account acc = newAccount('Boundaries', repA.Id);
        // "today" = 15 Mar 2026  =>  range is 1 Apr 2025 .. 31 Mar 2026 (crosses a year).
        Date today = Date.newInstance(2026, 3, 15);
        insert new List<Sale__c>{
            newSale(acc.Id, Date.newInstance(2025, 3, 31), 1), // day before the range - excluded
            newSale(acc.Id, Date.newInstance(2025, 4, 1), 10), // first day - included
            newSale(acc.Id, Date.newInstance(2025, 12, 31), 100), // year end - included
            newSale(acc.Id, Date.newInstance(2026, 1, 1), 1000), // year start - included
            newSale(acc.Id, Date.newInstance(2026, 3, 31), 10000), // last day of current month - included
            newSale(acc.Id, Date.newInstance(2026, 4, 1), 100000) // next month - excluded
        };

        SalesSummaryController.Summary summary = SalesSummaryController.buildSummary(repA.Id, today);

        Assert.areEqual(11110, summary.total);
        Assert.areEqual(4, summary.saleCount);
        Assert.areEqual(2025, summary.months[0].year);
        Assert.areEqual(4, summary.months[0].month);
        Assert.areEqual(10, summary.months[0].total);
        Assert.areEqual(2025, summary.months[8].year);
        Assert.areEqual(12, summary.months[8].month);
        Assert.areEqual(100, summary.months[8].total);
        Assert.areEqual(2026, summary.months[9].year);
        Assert.areEqual(1, summary.months[9].month);
        Assert.areEqual(2026, summary.months[11].year);
        Assert.areEqual(3, summary.months[11].month);
        Assert.areEqual(10000, summary.months[11].total);
    }

    @IsTest
    static void monthsBelowThresholdAreFlagged() {
        User repA = user(REP_A);
        Account acc = newAccount('Threshold', repA.Id);
        Decimal threshold = SalesSummaryController.getLowSalesThreshold();
        Date today = Date.newInstance(2026, 6, 10);
        insert new List<Sale__c>{
            newSale(acc.Id, Date.newInstance(2026, 6, 1), threshold - 0.01), // just below
            newSale(acc.Id, Date.newInstance(2026, 5, 1), threshold), // exactly the threshold
            newSale(acc.Id, Date.newInstance(2026, 4, 1), threshold / 2), // two small sales that
            newSale(acc.Id, Date.newInstance(2026, 4, 2), threshold / 2) //   together reach it
        };

        SalesSummaryController.Summary summary = SalesSummaryController.buildSummary(repA.Id, today);

        Assert.areEqual(threshold, summary.lowSalesThreshold);
        Assert.isTrue(summary.months[11].isLowSales, 'June: below threshold');
        Assert.isFalse(summary.months[10].isLowSales, 'May: equal to threshold is not "less than"');
        Assert.isFalse(summary.months[9].isLowSales, 'April: the month total counts, not single sales');
        Assert.isFalse(summary.months[8].isLowSales, 'March: no sales - not flagged');
    }

    @IsTest
    static void thresholdComesFromCustomMetadata() {
        Sales_Summary_Setting__mdt setting = Sales_Summary_Setting__mdt.getInstance(SalesSummaryController.SETTING_RECORD);
        Decimal expected = setting?.Low_Sales_Threshold__c ?? SalesSummaryController.DEFAULT_LOW_SALES_THRESHOLD;
        Assert.areEqual(expected, SalesSummaryController.getLowSalesThreshold());
    }

    @IsTest
    static void amountsInOtherCurrenciesAreConvertedToCorporateCurrency() {
        if (!UserInfo.isMultiCurrencyOrganization()) {
            return; // nothing to convert in a single-currency org
        }
        List<SObject> currencies = Database.query(
            'SELECT IsoCode, ConversionRate, IsCorporate FROM CurrencyType WHERE IsActive = true ORDER BY IsCorporate DESC'
        );
        if (currencies.size() < 2) {
            return;
        }
        String corporateIso = (String) currencies[0].get('IsoCode');
        String foreignIso = (String) currencies[1].get('IsoCode');
        Decimal foreignRate = (Decimal) currencies[1].get('ConversionRate'); // foreign units per 1 corporate unit

        User repA = user(REP_A);
        Account acc = newAccount('Multi Currency', repA.Id);
        Sale__c corporateSale = newSale(acc.Id, Date.today(), 1000);
        corporateSale.put('CurrencyIsoCode', corporateIso);
        Sale__c foreignSale = newSale(acc.Id, Date.today(), 100);
        foreignSale.put('CurrencyIsoCode', foreignIso);
        insert new List<Sale__c>{ corporateSale, foreignSale };

        SalesSummaryController.Summary summary;
        System.runAs(repA) {
            summary = SalesSummaryController.getMonthlySummary(null);
        }

        Decimal expected = 1000 + 100 / foreignRate;
        Assert.areEqual(corporateIso, summary.currencyIsoCode, 'totals are in the corporate currency');
        Assert.isTrue(Math.abs(summary.total - expected) < 0.05, 'expected ~' + expected + ' but got ' + summary.total);
    }

    @IsTest
    static void handlesHundredsOfAccountsAndThousandsOfSales() {
        User repA = user(REP_A);
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(Name = 'Bulk ' + i, OwnerId = repA.Id));
        }
        insert accounts;

        Date thisMonth = Date.today().toStartOfMonth();
        List<Sale__c> sales = new List<Sale__c>();
        for (Account acc : accounts) {
            for (Integer m = 0; m < 12; m++) {
                sales.add(newSale(acc.Id, thisMonth.addMonths(-m), 10));
            }
        }
        insert sales; // 2,400 sales

        SalesSummaryController.Summary summary;
        Test.startTest();
        System.runAs(repA) {
            summary = SalesSummaryController.getMonthlySummary(null);
        }
        Integer queryRows = Limits.getQueryRows();
        Test.stopTest();

        Assert.areEqual(2400, summary.saleCount);
        Assert.areEqual(24000, summary.total);
        for (SalesSummaryController.MonthSummary month : summary.months) {
            Assert.areEqual(2000, month.total, 'each month: 200 accounts x 10');
        }
        Assert.isTrue(queryRows < Limits.getLimitQueryRows(), 'well within the query-rows limit');
    }

    // ---------------------------------------------------------------- permissions

    @IsTest
    static void salesRepCannotViewAnotherSalesperson() {
        User repA = user(REP_A);
        User repB = user(REP_B);

        System.runAs(repA) {
            try {
                SalesSummaryController.getMonthlySummary(repB.Id);
                Assert.fail('a rep must not see another rep\'s sales');
            } catch (AuraHandledException e) {
                Assert.areEqual(System.Label.SalesSummary_ErrorNoPermission, e.getMessage());
            }
        }
    }

    @IsTest
    static void salesManagerCanViewAnySalesperson() {
        User repB = user(REP_B);
        Account acc = newAccount('Manager View', repB.Id);
        insert newSale(acc.Id, Date.today(), 750);

        SalesSummaryController.Summary summary;
        System.runAs(user(MANAGER)) {
            Assert.isTrue(SalesSummaryController.canViewAnySalesperson());
            summary = SalesSummaryController.getMonthlySummary(repB.Id);
        }

        Assert.areEqual(repB.Id, summary.salespersonId);
        Assert.areEqual(750, summary.total);
        Assert.isTrue(summary.canViewAnySalesperson);
        Assert.areEqual(750 < summary.lowSalesThreshold, summary.months[11].isLowSales);
    }

    @IsTest
    static void userWithoutAccessToSalesGetsAnError() {
        // A user with no permission set has no access to Sale__c: USER_MODE rejects the query.
        User noAccess = newUser('no.access');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert noAccess;
        }
        System.runAs(noAccess) {
            try {
                SalesSummaryController.getMonthlySummary(null);
                Assert.fail('expected an error for a user without access to Sales');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    // ---------------------------------------------------------------- helpers

    private static User newUser(String key) {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard Platform User' LIMIT 1];
        String unique = key + '.' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(8);
        return new User(
            LastName = 'Test ' + key,
            Alias = key.left(8).replace('.', ''),
            Email = key + '@example.com',
            Username = unique + '@sales-summary.test',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Jerusalem',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
    }

    private static User user(String key) {
        return [SELECT Id, Name FROM User WHERE LastName = :('Test ' + key) LIMIT 1];
    }

    private static Id permissionSetId(String name) {
        return [SELECT Id FROM PermissionSet WHERE Name = :name LIMIT 1].Id;
    }

    private static Account newAccount(String name, Id ownerId) {
        Account acc = new Account(Name = name, OwnerId = ownerId);
        insert acc;
        return acc;
    }

    /**
     * A sale in the corporate currency. In a multi-currency org a new record otherwise gets the
     * creating user's personal currency, which would be converted when summed.
     */
    private static Sale__c newSale(Id accountId, Date saleDate, Decimal amount) {
        Sale__c sale = new Sale__c(Account__c = accountId, Sale_Date__c = saleDate, Amount__c = amount);
        if (UserInfo.isMultiCurrencyOrganization()) {
            sale.put('CurrencyIsoCode', corporateCurrency());
        }
        return sale;
    }

    private static String corporateIsoCode;
    private static String corporateCurrency() {
        if (corporateIsoCode == null) {
            List<SObject> corporate = Database.query('SELECT IsoCode FROM CurrencyType WHERE IsCorporate = true LIMIT 1');
            corporateIsoCode = (String) corporate[0].get('IsoCode');
        }
        return corporateIsoCode;
    }
}
