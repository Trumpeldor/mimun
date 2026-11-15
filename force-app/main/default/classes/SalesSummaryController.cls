/**
 * Server side of the Monthly Sales Summary component (LWC salesSummary).
 *
 * Returns, for one salesperson, the total sales of each of the last 12 calendar
 * months (including the current month) plus the 12-month grand total.
 *
 * Business rules
 *  - A sale belongs to the CURRENT owner of its Account (Sale__c is a master-detail
 *    child of Account, so it has no owner of its own). We therefore filter on
 *    Account__r.OwnerId - a sale follows the Account when its owner changes.
 *  - Only users with the Sales_Summary_View_Any_Salesperson custom permission
 *    (sales managers) may request another user's summary. Everyone else gets
 *    their own summary only. This is enforced here, not just in the UI.
 *  - Amounts are summed in the corporate currency (ILS). In a multi-currency org,
 *    SUM() in a GROUP BY query returns the value converted to the corporate currency.
 *  - Months that had sales totaling less than the configurable threshold
 *    (Sales_Summary_Setting__mdt.Default, 1000) are flagged as low.
 *
 * Scale: a single aggregate query grouped by calendar year/month returns at most
 * 12 rows, regardless of how many accounts and sales the salesperson has.
 * Security: the query runs in USER_MODE (object, field and sharing access of the
 * running user are enforced).
 */
public with sharing class SalesSummaryController {
    @TestVisible
    private static final String VIEW_ANY_PERMISSION = 'Sales_Summary_View_Any_Salesperson';
    @TestVisible
    private static final String SETTING_RECORD = 'Default';
    @TestVisible
    private static final Decimal DEFAULT_LOW_SALES_THRESHOLD = 1000;
    @TestVisible
    private static final Integer MONTHS_IN_SUMMARY = 12;

    /**
     * @param salespersonId the user whose sales to summarize; null = the running user
     * @return the 12-month summary, oldest month first
     */
    @AuraEnabled(cacheable=true)
    public static Summary getMonthlySummary(Id salespersonId) {
        Id runningUserId = UserInfo.getUserId();
        Id targetUserId = salespersonId == null ? runningUserId : salespersonId;

        if (targetUserId != runningUserId && !canViewAnySalesperson()) {
            throw newAuraException(System.Label.SalesSummary_ErrorNoPermission);
        }

        try {
            return buildSummary(targetUserId, Date.today());
        } catch (Exception e) {
            // Log the details for admins; show the user a generic message, so internal details
            // (field names, query errors) are never exposed in the UI.
            System.debug(LoggingLevel.ERROR, 'Sales summary failed: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw newAuraException(System.Label.SalesSummary_ErrorGeneric);
        }
    }

    /** True for sales managers (users holding the custom permission). */
    public static Boolean canViewAnySalesperson() {
        return FeatureManagement.checkPermission(VIEW_ANY_PERMISSION);
    }

    @TestVisible
    private static Summary buildSummary(Id salespersonId, Date today) {
        Date firstMonth = today.toStartOfMonth().addMonths(-(MONTHS_IN_SUMMARY - 1));
        Date afterLastMonth = today.toStartOfMonth().addMonths(1);

        Map<String, Object> binds = new Map<String, Object>{
            'salespersonId' => salespersonId,
            'firstMonth' => firstMonth,
            'afterLastMonth' => afterLastMonth
        };
        List<AggregateResult> rows = Database.queryWithBinds(
            'SELECT CALENDAR_YEAR(Sale_Date__c) yr, CALENDAR_MONTH(Sale_Date__c) mon, ' +
                'SUM(Amount__c) total, COUNT(Id) saleCount ' +
                'FROM Sale__c ' +
                'WHERE Account__r.OwnerId = :salespersonId ' +
                'AND Sale_Date__c >= :firstMonth AND Sale_Date__c < :afterLastMonth ' +
                'GROUP BY CALENDAR_YEAR(Sale_Date__c), CALENDAR_MONTH(Sale_Date__c)',
            binds,
            AccessLevel.USER_MODE
        );

        Map<String, AggregateResult> rowByMonth = new Map<String, AggregateResult>();
        for (AggregateResult row : rows) {
            rowByMonth.put(monthKey((Integer) row.get('yr'), (Integer) row.get('mon')), row);
        }

        Summary result = new Summary();
        result.salespersonId = salespersonId;
        result.salespersonName = getUserName(salespersonId);
        result.currencyIsoCode = getCorporateCurrency();
        result.lowSalesThreshold = getLowSalesThreshold();
        result.canViewAnySalesperson = canViewAnySalesperson();

        // Always return all 12 months (months without sales show 0), oldest first.
        for (Integer i = 0; i < MONTHS_IN_SUMMARY; i++) {
            Date monthStart = firstMonth.addMonths(i);
            AggregateResult row = rowByMonth.get(monthKey(monthStart.year(), monthStart.month()));

            MonthSummary month = new MonthSummary();
            month.year = monthStart.year();
            month.month = monthStart.month();
            month.key = monthKey(month.year, month.month);
            month.saleCount = row == null ? 0 : (Integer) row.get('saleCount');
            month.total = row == null ? 0 : (Decimal) row.get('total');
            month.isLowSales = month.saleCount > 0 && month.total < result.lowSalesThreshold;

            result.months.add(month);
            result.total += month.total;
            result.saleCount += month.saleCount;
        }
        result.hasSales = result.saleCount > 0;
        return result;
    }

    @TestVisible
    private static Decimal getLowSalesThreshold() {
        Sales_Summary_Setting__mdt setting = Sales_Summary_Setting__mdt.getInstance(SETTING_RECORD);
        return setting?.Low_Sales_Threshold__c ?? DEFAULT_LOW_SALES_THRESHOLD;
    }

    /** The currency SUM() results are expressed in: the corporate currency in a multi-currency org. */
    private static String getCorporateCurrency() {
        if (UserInfo.isMultiCurrencyOrganization()) {
            // Dynamic so the class also compiles in single-currency orgs.
            List<SObject> corporate = Database.query('SELECT IsoCode FROM CurrencyType WHERE IsCorporate = true LIMIT 1');
            if (!corporate.isEmpty()) {
                return (String) corporate[0].get('IsoCode');
            }
        }
        return UserInfo.getDefaultCurrency();
    }

    private static String getUserName(Id userId) {
        List<User> users = [SELECT Name FROM User WHERE Id = :userId WITH USER_MODE LIMIT 1];
        return users.isEmpty() ? null : users[0].Name;
    }

    private static String monthKey(Integer year, Integer month) {
        return year + '-' + String.valueOf(month).leftPad(2, '0');
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message); // so the message is also visible in Apex tests
        return e;
    }

    public class Summary {
        @AuraEnabled
        public Id salespersonId;
        @AuraEnabled
        public String salespersonName;
        @AuraEnabled
        public String currencyIsoCode;
        @AuraEnabled
        public Decimal lowSalesThreshold;
        @AuraEnabled
        public Boolean canViewAnySalesperson;
        @AuraEnabled
        public Boolean hasSales = false;
        @AuraEnabled
        public Integer saleCount = 0;
        @AuraEnabled
        public Decimal total = 0;
        @AuraEnabled
        public List<MonthSummary> months = new List<MonthSummary>();
    }

    public class MonthSummary {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Integer year;
        @AuraEnabled
        public Integer month;
        @AuraEnabled
        public Decimal total;
        @AuraEnabled
        public Integer saleCount;
        @AuraEnabled
        public Boolean isLowSales;
    }
}
