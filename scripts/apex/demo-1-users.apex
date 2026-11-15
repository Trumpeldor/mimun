// Demo data, step 1 of 2: salespeople and a sales manager (Salesforce Platform licenses).
// Run:  sf apex run -f scripts/apex/demo-1-users.apex
// Safe to re-run: existing demo users are updated, not duplicated. No welcome emails are sent.
//
//   Dana Levi      Sales Rep      Israel, Hebrew UI, ILS     -> sees the component in Hebrew (RTL)
//   Michael Carter Sales Rep      US, English UI, USD        -> sells in USD, converted to ILS
//   Noa Cohen      Sales Manager  Israel, English UI, ILS    -> may pick any salesperson; owns no customers
//   Tom Becker     (inactive)     former rep                 -> must NOT appear in the lookup
// The running admin also gets the Sales Manager permission set.

String orgSuffix = UserInfo.getOrganizationId().left(15).toLowerCase();
Id platformProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard Platform User' LIMIT 1].Id;

// key => FirstName, LastName, Language, Locale, TimeZone, Currency, Active, PermissionSet
Map<String, List<Object>> demoUsers = new Map<String, List<Object>>{
    'dana.levi' => new List<Object>{ 'Dana', 'Levi', 'iw', 'iw_IL', 'Asia/Jerusalem', 'ILS', true, 'Sales_Summary_Sales_Rep' },
    'michael.carter' => new List<Object>{ 'Michael', 'Carter', 'en_US', 'en_US', 'America/New_York', 'USD', true, 'Sales_Summary_Sales_Rep' },
    'noa.cohen' => new List<Object>{ 'Noa', 'Cohen', 'en_US', 'en_US', 'Asia/Jerusalem', 'ILS', true, 'Sales_Summary_Sales_Manager' },
    'tom.becker' => new List<Object>{ 'Tom', 'Becker', 'en_US', 'en_US', 'America/New_York', 'USD', false, null }
};

Map<String, User> existing = new Map<String, User>();
for (User u : [SELECT Id, Username FROM User WHERE Username LIKE :('%.' + orgSuffix + '@sales-summary.demo')]) {
    existing.put(u.Username, u);
}

List<User> users = new List<User>();
Map<String, String> permSetByUsername = new Map<String, String>(); // by Username: stable, unlike an sObject key
for (String key : demoUsers.keySet()) {
    List<Object> d = demoUsers.get(key);
    String username = key + '.' + orgSuffix + '@sales-summary.demo';
    User u = existing.containsKey(username) ? existing.get(username) : new User(Username = username, ProfileId = platformProfileId);
    u.FirstName = (String) d[0];
    u.LastName = (String) d[1];
    u.Alias = ((String) d[0]).left(1) + ((String) d[1]).left(4);
    u.Email = key + '@example.com';
    u.LanguageLocaleKey = (String) d[2];
    u.LocaleSidKey = (String) d[3];
    u.TimeZoneSidKey = (String) d[4];
    u.put('DefaultCurrencyIsoCode', (String) d[5]);
    u.EmailEncodingKey = 'UTF-8';
    u.UserPermissionsSFContentUser = false; // not needed; the org has few CRM Content feature licenses
    u.IsActive = (Boolean) d[6];
    u.Title = d[7] == 'Sales_Summary_Sales_Manager' ? 'Sales Manager' : 'Sales Representative';
    users.add(u);
    permSetByUsername.put(u.Username, (String) d[7]);
}
List<User> toInsert = new List<User>();
List<User> toUpdate = new List<User>();
for (User u : users) {
    (u.Id == null ? toInsert : toUpdate).add(u);
}
Database.DMLOptions noEmail = new Database.DMLOptions(); // no welcome / password emails
noEmail.EmailHeader.triggerUserEmail = false;
noEmail.EmailHeader.triggerAutoResponseEmail = false;
noEmail.EmailHeader.triggerOtherEmail = false;
noEmail.OptAllOrNone = true;
Database.insert(toInsert, noEmail);
update toUpdate;
System.debug('Users created: ' + toInsert.size() + ', updated: ' + toUpdate.size());

// Permission sets
Map<String, Id> permSetIds = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('Sales_Summary_Sales_Rep', 'Sales_Summary_Sales_Manager')]) {
    permSetIds.put(ps.Name, ps.Id);
}
Map<Id, String> wanted = new Map<Id, String>();
for (User u : users) {
    String ps = permSetByUsername.get(u.Username);
    if (ps != null) {
        wanted.put(u.Id, ps);
    }
}
wanted.put(UserInfo.getUserId(), 'Sales_Summary_Sales_Manager'); // the admin can test as a manager

Set<String> have = new Set<String>();
for (PermissionSetAssignment a : [SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId IN :wanted.keySet()]) {
    have.add(a.AssigneeId + ':' + a.PermissionSetId);
}
List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
for (Id userId : wanted.keySet()) {
    Id psId = permSetIds.get(wanted.get(userId));
    if (!have.contains(userId + ':' + psId)) {
        assignments.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = psId));
    }
}
insert assignments;
System.debug('Permission set assignments added: ' + assignments.size());
