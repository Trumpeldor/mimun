// Shared test helpers for the salesSummary Jest tests (not a test file itself).

export const CURRENT_USER_ID = '005000000000001AAA';

/**
 * A 12-month summary as returned by SalesSummaryController (Dec 2025 - Nov 2026).
 * @param totals map of month index (0-11) -> [total, saleCount]
 */
export function summary(totals = {}, overrides = {}) {
    const threshold = 1000;
    const months = [];
    let total = 0;
    let saleCount = 0;
    for (let i = 0; i < 12; i++) {
        const year = i === 0 ? 2025 : 2026;
        const month = i === 0 ? 12 : i;
        const [monthTotal, count] = totals[i] || [0, 0];
        months.push({
            key: `${year}-${String(month).padStart(2, '0')}`,
            year,
            month,
            total: monthTotal,
            saleCount: count,
            isLowSales: count > 0 && monthTotal < threshold
        });
        total += monthTotal;
        saleCount += count;
    }
    return {
        salespersonId: CURRENT_USER_ID,
        salespersonName: 'Dana Levi',
        currencyIsoCode: 'ILS',
        lowSalesThreshold: threshold,
        hasSales: saleCount > 0,
        saleCount,
        total,
        months,
        ...overrides
    };
}

export const flush = () => Promise.resolve();

export function removeAll() {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
}
