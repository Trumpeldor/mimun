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
const DANA_ID = '005000000000002AAA';
const HANDOVER_KEY = 'salesSummary.selectionAfterLanguageChange.' + CURRENT_USER_ID;

describe('c-sales-summary (sales manager)', () => {
    afterEach(() => {
        removeAll();
        window.sessionStorage.clear();
        jest.clearAllMocks();
    });

    it('opens the lookup, defaulting to the current user', async () => {
        const element = render();
        await flush();

        expect(picker(element).disabled).toBe(false);
        expect(picker(element).value).toBe(CURRENT_USER_ID);
        expect(picker(element).fieldLevelHelp).toBeFalsy();
    });

    it('keeps the selected salesperson through ONE reload after a language change, not after a normal refresh', async () => {
        const first = render();
        await flush();
        picker(first).dispatchEvent(new CustomEvent('change', { detail: { recordId: DANA_ID } }));
        await flush();

        // A normal refresh (no language change): back to the current user.
        removeAll();
        const refreshed = render();
        await flush();
        expect(picker(refreshed).value).toBe(CURRENT_USER_ID);

        // Select Dana again, then the language switcher announces the change just before its reload.
        picker(refreshed).dispatchEvent(new CustomEvent('change', { detail: { recordId: DANA_ID } }));
        await flush();
        refreshed.shadowRoot.querySelector('c-language-switcher').dispatchEvent(new CustomEvent('languagechange'));
        expect(window.sessionStorage.getItem(HANDOVER_KEY)).toBe(DANA_ID);

        // The reload after the language change: Dana is restored, and the hand-over is consumed.
        removeAll();
        const afterLanguageChange = render();
        await flush();
        expect(picker(afterLanguageChange).value).toBe(DANA_ID);
        expect(window.sessionStorage.getItem(HANDOVER_KEY)).toBeNull();

        // Any later load: the current user again.
        removeAll();
        const later = render();
        await flush();
        expect(picker(later).value).toBe(CURRENT_USER_ID);
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
