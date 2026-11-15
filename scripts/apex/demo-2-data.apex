// Demo data, step 2 of 2: customers (Accounts) and a few hundred Sales, relative to TODAY.
// Run after demo-1-users.apex:  sf apex run -f scripts/apex/demo-2-data.apex
// Safe to re-run: previous demo Accounts (AccountNumber DEMO-*) and their Sales are deleted first.
//
// What it demonstrates (months are relative to the current month, 0 = this month):
//   Dana Levi (ILS)     - month -4 has a single small sale (650 ILS)        -> red
//                       - month -7 has no sales                             -> 0, not red
//                       - "Negev Solar" was Michael's customer and moved to Dana: all its sales count for Dana
//   Michael Carter (USD)- month -2: one 200 USD sale (= ~740 ILS)           -> red
//                       - month -9: 300 USD (= ~1,110 ILS)                  -> NOT red (threshold is in ILS)
//   Noa Cohen (manager) - owns no customers                                 -> "no sales" toast
//   Months -12 and -13 have sales that must NOT be included (outside the 12-month window).

String orgSuffix = UserInfo.getOrganizationId().left(15).toLowerCase();
Map<String, Id> userIds = new Map<String, Id>();
for (User u : [SELECT Id, Username FROM User WHERE Username LIKE :('%.' + orgSuffix + '@sales-summary.demo')]) {
    userIds.put(u.Username.substringBefore('.' + orgSuffix), u.Id);
}
Id dana = userIds.get('dana.levi');
Id michael = userIds.get('michael.carter');
System.assertNotEquals(null, dana, 'Run demo-1-users.apex first');

delete [SELECT Id FROM Account WHERE AccountNumber LIKE 'DEMO-%'];

// Deterministic pseudo-random numbers, so every run produces the same data.
Long seed = 20260615;
List<Long> seedHolder = new List<Long>{ seed };

// Accounts: name, owner, currency
List<List<Object>> accountDefs = new List<List<Object>>{
    new List<Object>{ 'Galil Software Ltd', dana, 'ILS' },
    new List<Object>{ 'Carmel Foods Ltd', dana, 'ILS' },
    new List<Object>{ 'Tavor Logistics', dana, 'ILS' },
    new List<Object>{ 'Yarkon Media', dana, 'ILS' },
    new List<Object>{ 'Hermon Pharma', dana, 'ILS' },
    new List<Object>{ 'Negev Solar Ltd', michael, 'ILS' }, // moves to Dana below
    new List<Object>{ 'Hudson Retail Inc', michael, 'USD' },
    new List<Object>{ 'Pacific Analytics', michael, 'USD' },
    new List<Object>{ 'Lone Star Energy', michael, 'USD' },
    new List<Object>{ 'Evergreen Health', michael, 'USD' },
    new List<Object>{ 'Great Lakes Supply', michael, 'USD' }
};
List<Account> accounts = new List<Account>();
for (Integer i = 0; i < accountDefs.size(); i++) {
    Account a = new Account(
        Name = (String) accountDefs[i][0],
        OwnerId = (Id) accountDefs[i][1],
        AccountNumber = 'DEMO-' + String.valueOf(i + 1).leftPad(3, '0'),
        BillingCountry = accountDefs[i][2] == 'USD' ? 'United States' : 'Israel'
    );
    a.put('CurrencyIsoCode', (String) accountDefs[i][2]);
    accounts.add(a);
}
insert accounts;

Date thisMonth = Date.today().toStartOfMonth();
List<Sale__c> sales = new List<Sale__c>();
for (Account a : accounts) {
    Boolean isUsd = a.get('CurrencyIsoCode') == 'USD';
    Boolean isDana = a.OwnerId == dana || a.Name == 'Negev Solar Ltd';
    for (Integer m = -13; m <= 0; m++) {
        // Special months, handled after the loop
        if (isDana && (m == -4 || m == -7)) continue;
        if (!isDana && (m == -2 || m == -9)) continue;

        seedHolder[0] = Math.mod(seedHolder[0] * 1103515245L + 12345L, 2147483648L);
        Integer count = 2 + (Integer) Math.mod(seedHolder[0], 4); // 2-5 sales per account per month
        for (Integer s = 0; s < count; s++) {
            seedHolder[0] = Math.mod(seedHolder[0] * 1103515245L + 12345L, 2147483648L);
            Integer day = 1 + (Integer) Math.mod(seedHolder[0], 28);
            seedHolder[0] = Math.mod(seedHolder[0] * 1103515245L + 12345L, 2147483648L);
            Decimal amount = isUsd
                ? 150 + Math.mod(seedHolder[0], 2350) // 150 - 2,500 USD
                : 400 + Math.mod(seedHolder[0], 7600); // 400 - 8,000 ILS
            Date saleDate = thisMonth.addMonths(m).addDays(day - 1);
            if (saleDate > Date.today()) {
                saleDate = Date.today(); // no future-dated sales in the current month
            }
            Sale__c sale = new Sale__c(Account__c = a.Id, Sale_Date__c = saleDate, Amount__c = amount);
            sale.put('CurrencyIsoCode', a.get('CurrencyIsoCode'));
            sales.add(sale);
        }
    }
}

Map<String, Account> byName = new Map<String, Account>();
for (Account a : accounts) {
    byName.put(a.Name, a);
}
// Dana, month -4: one small sale -> red. Month -7: nothing.
Sale__c small = new Sale__c(Account__c = byName.get('Carmel Foods Ltd').Id, Sale_Date__c = thisMonth.addMonths(-4).addDays(9), Amount__c = 650);
small.put('CurrencyIsoCode', 'ILS');
sales.add(small);
// Michael, month -2: 200 USD (~740 ILS) -> red. Month -9: 300 USD (~1,110 ILS) -> not red.
Sale__c usdSmall = new Sale__c(Account__c = byName.get('Hudson Retail Inc').Id, Sale_Date__c = thisMonth.addMonths(-2).addDays(4), Amount__c = 200);
usdSmall.put('CurrencyIsoCode', 'USD');
sales.add(usdSmall);
Sale__c usdBorder = new Sale__c(Account__c = byName.get('Pacific Analytics').Id, Sale_Date__c = thisMonth.addMonths(-9).addDays(14), Amount__c = 300);
usdBorder.put('CurrencyIsoCode', 'USD');
sales.add(usdBorder);

insert sales;

// The customer changes salesperson: Negev Solar moves from Michael to Dana.
Account negev = byName.get('Negev Solar Ltd');
negev.OwnerId = dana;
negev.Description = 'Demo: was owned by Michael Carter; reassigned to Dana Levi. All of its sales now count for Dana.';
update negev;

System.debug('Demo accounts: ' + accounts.size() + ', sales: ' + sales.size());
