// Sales manager view (has the "View Any Salesperson" custom permission).
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
jest.mock('@salesforce/customPermission/Sales_Summary_View_Any_Salesperson', () => ({ default: true }), {
    virtual: true
});
jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

function render() {
    const element = createElement('c-sales-summary', { is: SalesSummary });
    document.body.appendChild(element);
    return element;
}
const picker = (element) => element.shadowRoot.querySelector('lightning-record-picker');

describe('c-sales-summary (sales manager)', () => {
    afterEach(() => {
        removeAll();
        jest.clearAllMocks();
    });

    it('opens the lookup, defaulting to the current user', async () => {
        const element = render();
        await flush();

        expect(picker(element).disabled).toBe(false);
        expect(picker(element).value).toBe(CURRENT_USER_ID);
        expect(picker(element).fieldLevelHelp).toBeFalsy();
    });

    it('asks to pick a salesperson when the lookup is cleared', async () => {
        const element = render();
        getMonthlySummary.emit(summary({ 0: [5000, 3] }));
        await flush();
        expect(element.shadowRoot.querySelector('table')).not.toBeNull();

        picker(element).dispatchEvent(new CustomEvent('change', { detail: { recordId: null } }));
        await flush();

        expect(element.shadowRoot.querySelector('table')).toBeNull();
        expect(element.shadowRoot.textContent).toContain('c.SalesSummary_SelectSalesperson');
    });
});
