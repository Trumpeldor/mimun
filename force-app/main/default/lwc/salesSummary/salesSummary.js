import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getMonthlySummary from '@salesforce/apex/SalesSummaryController.getMonthlySummary';
import CURRENT_USER_ID from '@salesforce/user/Id';
import LOCALE from '@salesforce/i18n/locale';
import LANG from '@salesforce/i18n/lang';
import canViewAnySalesperson from '@salesforce/customPermission/Sales_Summary_View_Any_Salesperson';

import TITLE from '@salesforce/label/c.SalesSummary_Title';
import SALESPERSON from '@salesforce/label/c.SalesSummary_Salesperson';
import OWN_SALES_ONLY_HELP from '@salesforce/label/c.SalesSummary_OwnSalesOnlyHelp';
import SELECT_SALESPERSON from '@salesforce/label/c.SalesSummary_SelectSalesperson';
import COLUMN_MONTH from '@salesforce/label/c.SalesSummary_ColumnMonth';
import COLUMN_YEAR from '@salesforce/label/c.SalesSummary_ColumnYear';
import COLUMN_TOTAL from '@salesforce/label/c.SalesSummary_ColumnTotal';
import GRAND_TOTAL from '@salesforce/label/c.SalesSummary_GrandTotal';
import LOW_SALES_LEGEND from '@salesforce/label/c.SalesSummary_LowSalesLegend';
import NO_SALES_TITLE from '@salesforce/label/c.SalesSummary_NoSalesTitle';
import NO_SALES_MESSAGE from '@salesforce/label/c.SalesSummary_NoSalesMessage';
import ERROR_TITLE from '@salesforce/label/c.SalesSummary_ErrorTitle';
import REFRESH from '@salesforce/label/c.SalesSummary_Refresh';
import LOADING from '@salesforce/label/c.SalesSummary_Loading';

const LOW_SALES_CLASS = 'slds-text-color_error';

// Month names are words, so they follow the user's LANGUAGE (like the labels), while amounts
// follow the user's LOCALE (number/currency format). Salesforce uses "iw" for Hebrew; Intl expects "he".
const MONTH_NAME_LANGUAGE = LANG && LANG.toLowerCase().startsWith('iw') ? 'he' : LANG;

// Only active, internal users can be picked. The built-in Analytics system users ("Integration User",
// "Security User") are also 'Standard' users, so they are excluded by profile.
// Note: the record picker filters through the GraphQL API, which can follow only ONE relationship
// (Profile.Name works; Profile.UserLicense.Name fails the search).
const ACTIVE_USERS_FILTER = {
    criteria: [
        { fieldPath: 'IsActive', operator: 'eq', value: true },
        { fieldPath: 'UserType', operator: 'eq', value: 'Standard' },
        { fieldPath: 'Profile.Name', operator: 'nin', value: ['Analytics Cloud Integration User', 'Analytics Cloud Security User'] }
    ]
};

export default class SalesSummary extends LightningElement {
    labels = {
        TITLE,
        SALESPERSON,
        OWN_SALES_ONLY_HELP,
        SELECT_SALESPERSON,
        COLUMN_MONTH,
        COLUMN_YEAR,
        COLUMN_TOTAL,
        GRAND_TOTAL,
        REFRESH,
        LOADING
    };
    userFilter = ACTIVE_USERS_FILTER;

    // Defaults to the current user. The only exception: right after a language switch, a manager gets
    // back the salesperson they had selected (see handleLanguageChange). A normal refresh (F5) or a
    // later visit starts on the current user again, as the task requires. undefined = lookup cleared.
    selectedUserId = (canViewAnySalesperson === true && takeSelectionAfterLanguageChange()) || CURRENT_USER_ID;
    summary;
    // Built once per server response (not in a getter).
    rows = [];
    isLoading = true;
    wiredSummaryResult;

    /** Sales managers (custom permission) may choose any salesperson; everyone else sees only themselves. */
    get canSelectSalesperson() {
        return canViewAnySalesperson === true;
    }

    get isPickerDisabled() {
        return !this.canSelectSalesperson;
    }

    get pickerHelpText() {
        return this.canSelectSalesperson ? null : OWN_SALES_ONLY_HELP;
    }

    get hasSelection() {
        return !!this.selectedUserId;
    }

    get showSelectPrompt() {
        return !this.hasSelection;
    }

    get showTable() {
        return this.hasSelection && !this.isLoading && this.summary?.hasSales === true;
    }

    buildRows(summary) {
        const monthFormat = new Intl.DateTimeFormat(MONTH_NAME_LANGUAGE, { month: 'long' });
        const lowSalesText = this.lowSalesLegend;
        return summary.months.map((m) => ({
            key: m.key,
            monthName: monthFormat.format(new Date(m.year, m.month - 1, 1)),
            yearText: String(m.year),
            total: m.total,
            currencyCode: summary.currencyIsoCode,
            isLowSales: m.isLowSales,
            rowClass: m.isLowSales ? LOW_SALES_CLASS : '',
            lowSalesText: m.isLowSales ? lowSalesText : null
        }));
    }

    get currencyCode() {
        return this.summary?.currencyIsoCode;
    }

    get lowSalesLegend() {
        if (!this.summary) {
            return '';
        }
        const threshold = new Intl.NumberFormat(LOCALE, {
            style: 'currency',
            currency: this.summary.currencyIsoCode,
            maximumFractionDigits: 0
        }).format(this.summary.lowSalesThreshold);
        return format(LOW_SALES_LEGEND, threshold);
    }

    @wire(getMonthlySummary, { salespersonId: '$selectedUserId' })
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        const { data, error } = result;
        if (data) {
            this.summary = data;
            this.rows = this.buildRows(data);
            this.isLoading = false;
            if (!data.hasSales) {
                this.toast(NO_SALES_TITLE, format(NO_SALES_MESSAGE, data.salespersonName), 'info');
            }
        } else if (error) {
            this.summary = undefined;
            this.rows = [];
            this.isLoading = false;
            this.toast(ERROR_TITLE, reduceError(error), 'error');
        }
    }

    handleSalespersonChange(event) {
        const recordId = event.detail.recordId || undefined;
        if (recordId === this.selectedUserId) {
            return; // same salesperson - nothing to reload
        }
        this.selectedUserId = recordId;
        this.summary = undefined;
        this.rows = [];
        this.isLoading = !!recordId;
    }

    async handleRefresh() {
        if (!this.wiredSummaryResult || !this.hasSelection) {
            return;
        }
        this.isLoading = true;
        try {
            await refreshApex(this.wiredSummaryResult);
        } finally {
            this.isLoading = false;
        }
    }

    /** The language switcher is about to reload the page: keep a manager's selection for that one reload. */
    handleLanguageChange() {
        if (this.canSelectSalesperson && this.selectedUserId) {
            keepSelectionForLanguageChange(this.selectedUserId);
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

// One-time hand-over of a manager's selected salesperson across the language-switch reload.
// Written only just before that reload, read once on the next load, and deleted right away - so a normal
// refresh always starts on the current user. Per user and per browser tab (sessionStorage).
const LANGUAGE_CHANGE_KEY = 'salesSummary.selectionAfterLanguageChange.' + CURRENT_USER_ID;
const USER_ID_PATTERN = /^005[a-zA-Z0-9]{12}([a-zA-Z0-9]{3})?$/;

function keepSelectionForLanguageChange(userId) {
    try {
        window.sessionStorage.setItem(LANGUAGE_CHANGE_KEY, userId);
    } catch {
        // storage unavailable - the page just opens on the current user
    }
}

function takeSelectionAfterLanguageChange() {
    try {
        const stored = window.sessionStorage.getItem(LANGUAGE_CHANGE_KEY);
        window.sessionStorage.removeItem(LANGUAGE_CHANGE_KEY);
        return stored && USER_ID_PATTERN.test(stored) ? stored : undefined;
    } catch {
        return undefined;
    }
}

/** Replaces {0}, {1}, ... in a custom label. */
function format(template, ...args) {
    return template.replace(/\{(\d+)\}/g, (match, i) => (args[i] !== undefined ? args[i] : match));
}

function reduceError(error) {
    if (Array.isArray(error?.body)) {
        return error.body.map((e) => e.message).join(', ');
    }
    return error?.body?.message || error?.message || String(error);
}
