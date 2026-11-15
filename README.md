# Monthly Sales Summary (Salesforce)

A Lightning page for sales managers and salespeople. For a chosen salesperson it shows the total sales of each of the
last 12 calendar months (including the current month). Months with sales under ₪1,000 are marked in red, and the
12-month total is shown under the table.

## Where to find it in the org

| What | Where |
| --- | --- |
| The component | App Launcher → **Sales Summary** app → **Sales Summary** tab |
| Customers and their sales | Same app → **Accounts** (each Account has a **Sales** related list) and **Sales** tabs |
| Low-sales threshold (₪1,000) | Setup → Custom Metadata Types → **Sales Summary Setting** → *Default* |
| Permissions | Setup → Permission Sets → **Sales Summary - Sales Rep** / **Sales Summary - Sales Manager**; Setup → Custom Permissions → **Sales Summary: View Any Salesperson** |
| Screen text (English + Hebrew) | Setup → Custom Labels (category *SalesSummary*); Hebrew in Translation Workbench |
| Currencies | Setup → Company Information → Currencies (multi-currency: **ILS** corporate, **USD** = 3.7 ILS) |

## What was built

### Data model
- **Sale (`Sale__c`)**: one row per sale.
  - **Account** (master-detail to Account): the customer.
  - **Sale Date** (Date).
  - **Amount** (Currency, must be > 0).
  - Currency (standard multi-currency field).
- The Sale has **no owner of its own**. Because of the master-detail relationship it always belongs to the Account's
  **current** owner, so when a customer moves to another salesperson, all of its past sales move too.
- **Sale Date is a Date, not a Date/Time**, so a sale can never move to a different month because of time zones
  (US / Israel).

### Component (`lwc/salesSummary`)
Built from standard components: `lightning-card`, `lightning-record-picker`, `lightning-formatted-number`,
`lightning-icon`, and toasts. The table itself is a plain table with standard SLDS table styles, not
`lightning-datatable`. The datatable re-measures its columns on every resize. When the page was right at the
scrollbar threshold (for example with the "Logged in as" banner shown), that caused an endless layout loop, and
the screen shook. A 12-row, read-only table doesn't need any of the datatable's features.

- **Salesperson lookup**: shows active users only (and only internal users, not portal or integration users).
  Defaults to the current user.
- **Table**: 12 rows (month name, year, total), oldest first. Months without sales show 0.
- **Red rows**: a month *that had sales* totaling less than the threshold is shown in red, with a warning icon so it
  is not signaled by color alone.
- **Grand total**: the 12-month total appears under the table.
- **No sales at all**: an info toast is shown instead of the table.
- **Refresh button**: reloads the data.

### Server (`classes/SalesSummaryController`)
- **One aggregate SOQL query**, grouped by calendar year and month, and filtered by `Account__r.OwnerId` and the
  12-month date range.
  - It returns at most 12 rows, however many accounts or sales the salesperson has. This keeps it fast and within
    governor limits with hundreds of accounts and thousands of sales.
  - The tests cover 200 accounts and 2,400 sales.
- **Runs in `USER_MODE`**: the running user's object, field and sharing access are enforced.
- **The permission rule is enforced on the server**, not only in the UI: a user without the custom permission who
  asks for another user's data gets an error.
- **Multi-currency**: `SUM()` in a `GROUP BY` query returns the amount converted to the corporate currency (ILS).
  A USD sale is therefore compared with the ₪1,000 threshold after conversion.

### Permissions
| Role | Assign | Result |
| --- | --- | --- |
| Salesperson | **Sales Summary - Sales Rep** | Sees only their own data. The lookup is locked to themselves. |
| Sales manager | **Sales Summary - Sales Manager** (includes the **Sales Summary: View Any Salesperson** custom permission) | Can choose any active salesperson. |

The component reads the custom permission (`@salesforce/customPermission/...`) to lock the lookup. The Apex
controller checks it again with `FeatureManagement.checkPermission`.

### Two languages
All screen text is in Custom Labels (English) with Hebrew translations. Each user sees the screen in their own
Salesforce language. Lightning switches to right-to-left layout for Hebrew automatically. Month names follow the
user's **language** (like the labels), while amounts follow the user's **locale** (number and currency format). To add another language, translate the 14 *SalesSummary* labels in Translation
Workbench. No code changes are needed.

### Tests
`SalesSummaryControllerTest`: 11 tests, 99% coverage of the controller. They cover:
- the default to the current user;
- the 12-month window, including its first and last days and a year change;
- a sale following the customer to its new owner;
- the threshold, including exactly ₪1,000 and a month whose total reaches it through several small sales;
- no sales at all;
- currency conversion;
- bulk data;
- a salesperson being blocked from another user's data, a manager being allowed, and a user with no access.

## How to test

Demo data has been loaded. All amounts in the component are in ILS.

| User | Role | What to check |
| --- | --- | --- |
| **Dana Levi** | Salesperson, Hebrew UI | Lookup is locked to herself. The screen is in Hebrew (right-to-left). One month (4 months ago) has a single ₪650 sale, shown in red. One month (7 months ago) has ₪0 and is *not* red. Customer *Negev Solar Ltd* was moved to her from Michael, and its sales count for her. |
| **Michael Carter** | Salesperson, sells in USD | 2 months ago: 200 USD ≈ ₪740, shown in red. 9 months ago: 300 USD ≈ ₪1,110, *not* red, because the threshold applies after conversion to ILS. |
| **Noa Cohen** | Sales manager | Can pick any salesperson. Her own view shows the "No sales" toast (she has no customers). |
| **Tom Becker** | Inactive former salesperson | Must **not** appear in the lookup. |

The system administrator also has the Sales Manager permission set, so the component can be tried directly as a
manager. To see it as a salesperson: Setup → Users → *Dana Levi* → **Login**.

Other checks:
- Change an Account's owner, then click refresh: its sales move to the new salesperson.
- Change the threshold in Custom Metadata, then refresh: the red marking follows the new value with no deployment.

## Business assumptions
1. **"Current month" and the 12-month window are calendar months in the viewing user's time zone.** A sale's month
   is taken from its Sale Date (a date, so no time-zone shift).
2. **Amounts are summarized in ILS** (the corporate currency). Sales may be recorded in ILS or USD and are converted
   at the org's exchange rate (1 USD = 3.7 ILS, set by an admin). Dated exchange rates were not enabled.
3. **Red means "the month had at least one sale and its total is below ₪1,000".** A month with no sales shows 0 and
   is not red. Exactly ₪1,000 is not red. The threshold is configurable because a follow-up requirement was
   announced.
4. **A sale belongs to the Account's current owner.** Past owners keep no credit (as the task requires). There is
   no history of who owned the Account when the sale was made.
5. **Sale amounts are positive.** Returns and refunds are out of scope.
6. **The lookup lists active internal (Standard) users**, not only users holding the Sales Rep permission set. The
   standard record picker can't filter by permission set. The custom permission still controls who may *choose*
   another user.
7. **Managers' visibility:** the query runs in user mode. A manager sees a salesperson's full totals when they can
   see that salesperson's Accounts. That is true here (Account sharing is Public Read/Write); with private sharing it
   would come from the role hierarchy or sharing rules.

## Project structure / deployment

Standard Salesforce DX project (`force-app/main/default`).

```bash
sf project deploy start -d force-app -o <org>          # deploy everything
sf apex run test -n SalesSummaryControllerTest -c -o <org>
sf apex run -f scripts/apex/demo-1-users.apex -o <org>  # demo users + permission sets
sf apex run -f scripts/apex/demo-2-data.apex -o <org>   # demo customers and sales (re-runnable)
```

Multi-currency is turned on in `settings/Currency.settings-meta.xml`. On a new org, first deploy
`isMultiCurrencyActivationAllowed=true` by itself, then `enableMultiCurrency=true`, and then add the currencies
(ILS corporate, USD). Multi-currency can't be turned off once enabled.

To log in as the demo users (they have no passwords), turn on **Administrators Can Log in as Any User**
(Setup → Login Access Policies). This is done by hand rather than deployed from the repo.
