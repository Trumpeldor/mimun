// Salesperson view (no "View Any Salesperson" custom permission). The manager view is in
// salesSummary.manager.test.js: the custom permission is read once per module load, so each
// permission setup gets its own test file.
import { createElement } from 'lwc';
import SalesSummary from 'c/salesSummary';
import getMonthlySummary from '@salesforce/apex/SalesSummaryController.getMonthlySummary';
import { CURRENT_USER_ID, summary, flush, removeAll } from './summaryFixture';

jest.mock(
    '@salesforce/apex/SalesSummaryController.getMonthlySummary',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock('@salesforce/customPermission/Sales_Summary_View_Any_Salesperson', () => ({ default: undefined }), {
    virtual: true
});
jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

function render() {
    const element = createElement('c-sales-summary', { is: SalesSummary });
    document.body.appendChild(element);
    return element;
}
const picker = (element) => element.shadowRoot.querySelector('lightning-record-picker');
const tableRows = (element) => [...element.shadowRoot.querySelectorAll('tbody tr')];

describe('c-sales-summary (salesperson)', () => {
    afterEach(() => {
        removeAll();
        jest.clearAllMocks();
    });

    it('locks the lookup to the current user, with a help text', async () => {
        const element = render();
        await flush();

        expect(picker(element).disabled).toBe(true);
        expect(picker(element).value).toBe(CURRENT_USER_ID);
        expect(picker(element).fieldLevelHelp).toBe('c.SalesSummary_OwnSalesOnlyHelp');
    });

    it('lists only active internal users, excludes system profiles, and follows at most one relationship', async () => {
        const element = render();
        await flush();
        const { criteria } = picker(element).filter;

        expect(criteria).toContainEqual({ fieldPath: 'IsActive', operator: 'eq', value: true });
        expect(criteria).toContainEqual({ fieldPath: 'UserType', operator: 'eq', value: 'Standard' });
        const profileRule = criteria.find((c) => c.fieldPath === 'Profile.Name');
        expect(profileRule.operator).toBe('nin');
        expect(profileRule.value).toEqual(
            expect.arrayContaining(['Analytics Cloud Integration User', 'Analytics Cloud Security User'])
        );
        // Regression guard: the record picker searches through GraphQL, which follows only ONE
        // relationship. A two-level path (e.g. Profile.UserLicense.Name) breaks every search.
        criteria.forEach((c) => expect(c.fieldPath.split('.').length).toBeLessThanOrEqual(2));
    });

    it('marks in red only months that had sales below the threshold', async () => {
        const element = render();
        // Month 3: one sale of 650 (low). Month 4: no sales (0, not low). Month 5: exactly 1000 (not low).
        getMonthlySummary.emit(summary({ 0: [5000, 3], 3: [650, 1], 5: [1000, 2] }));
        await flush();

        const rows = tableRows(element);
        expect(rows).toHaveLength(12);
        const red = rows.filter((tr) => tr.className.includes('slds-text-color_error'));
        expect(red).toEqual([rows[3]]);
        expect(rows[3].querySelector('lightning-icon').iconName).toBe('utility:warning');
        expect(rows[4].querySelector('lightning-icon')).toBeNull(); // month without sales
        expect(rows[5].querySelector('lightning-icon')).toBeNull(); // exactly the threshold
        expect(rows[0].querySelector('th').textContent).toBe('December');
        expect(rows[0].querySelectorAll('td')[0].textContent).toBe('2025');
    });

    it('shows the 12-month total and the legend under the table', async () => {
        const element = render();
        getMonthlySummary.emit(summary({ 0: [5000, 3], 3: [650, 1], 11: [2350, 2] }));
        await flush();

        const total = element.shadowRoot.querySelector('.grand-total lightning-formatted-number');
        expect(total.value).toBe(8000);
        expect(total.currencyCode).toBe('ILS');
        expect(element.shadowRoot.textContent).toContain('c.SalesSummary_GrandTotal');
        expect(element.shadowRoot.textContent).toContain('c.SalesSummary_LowSalesLegend');
    });

    it('shows a toast instead of the table when there are no sales at all', async () => {
        const element = render();
        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        getMonthlySummary.emit(summary());
        await flush();

        expect(toastHandler).toHaveBeenCalledTimes(1);
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('info');
        expect(element.shadowRoot.querySelector('table')).toBeNull();
    });
});
