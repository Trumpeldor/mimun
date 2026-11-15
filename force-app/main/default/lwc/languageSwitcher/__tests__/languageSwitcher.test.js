import { createElement } from 'lwc';
import LanguageSwitcher from 'c/languageSwitcher';
import setMyLanguage from '@salesforce/apex/UserLanguageController.setMyLanguage';

jest.mock('@salesforce/apex/UserLanguageController.setMyLanguage', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/i18n/lang', () => ({ default: 'en-US' }), { virtual: true });

// jsdom can't navigate, so replace window.location with a stub whose reload() we can observe.
const originalLocation = window.location;
beforeAll(() => {
    Object.defineProperty(window, 'location', { configurable: true, value: { reload: jest.fn() } });
});
afterAll(() => {
    Object.defineProperty(window, 'location', { configurable: true, value: originalLocation });
});

// Lets the awaited Apex promise and the code after it run (microtasks only, no timers).
const flush = () => [1, 2, 3, 4, 5].reduce((previous) => previous.then(() => undefined), Promise.resolve());

function render() {
    const element = createElement('c-language-switcher', { is: LanguageSwitcher });
    document.body.appendChild(element);
    return element;
}
const menu = (element) => element.shadowRoot.querySelector('lightning-button-menu');
const select = (element, value) => menu(element).dispatchEvent(new CustomEvent('select', { detail: { value } }));

describe('c-language-switcher', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('lists English and Hebrew in their own names, with a check mark on the current language', async () => {
        const element = render();
        await flush();

        const items = [...element.shadowRoot.querySelectorAll('lightning-menu-item')];
        expect(items.map((i) => [i.value, i.label, i.checked])).toEqual([
            ['en_US', 'English', true],
            ['iw', 'עברית', false]
        ]);
    });

    it('does nothing when the current language is chosen', async () => {
        const element = render();
        const changed = jest.fn();
        element.addEventListener('languagechange', changed);

        select(element, 'en_US');
        await flush();

        expect(setMyLanguage).not.toHaveBeenCalled();
        expect(changed).not.toHaveBeenCalled();
        expect(window.location.reload).not.toHaveBeenCalled();
    });

    it('saves the new language, announces it, then reloads the page', async () => {
        setMyLanguage.mockResolvedValue(undefined);
        const element = render();
        const order = [];
        element.addEventListener('languagechange', (e) => order.push('event:' + e.detail.language));
        window.location.reload.mockImplementation(() => order.push('reload'));

        select(element, 'iw');
        await flush();

        expect(setMyLanguage).toHaveBeenCalledWith({ languageKey: 'iw' });
        // The event must come BEFORE the reload, so the host can keep its state.
        expect(order).toEqual(['event:iw', 'reload']);
    });

    it('shows a generic error and does not reload when saving fails', async () => {
        setMyLanguage.mockRejectedValue({ body: { message: 'internal detail' } });
        const consoleError = jest.spyOn(console, 'error').mockImplementation(() => {});
        const element = render();
        const toast = jest.fn();
        element.addEventListener('lightning__showtoast', toast);

        select(element, 'iw');
        await flush();

        expect(window.location.reload).not.toHaveBeenCalled();
        expect(toast).toHaveBeenCalledTimes(1);
        const { title, message, variant } = toast.mock.calls[0][0].detail;
        expect([title, message, variant]).toEqual(['c.LanguageSwitcher_Error', 'c.LanguageSwitcher_ErrorDetail', 'error']);
        expect(message).not.toContain('internal detail');
        consoleError.mockRestore();
    });
});
