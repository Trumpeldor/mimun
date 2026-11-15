import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LANG from '@salesforce/i18n/lang';
import setMyLanguage from '@salesforce/apex/UserLanguageController.setMyLanguage';
import LANGUAGE from '@salesforce/label/c.LanguageSwitcher_Language';
import ERROR from '@salesforce/label/c.LanguageSwitcher_Error';
import ERROR_DETAIL from '@salesforce/label/c.LanguageSwitcher_ErrorDetail';

// Each language is shown in its own name, so it can be found whatever the current language is.
// value = Salesforce language key ("iw" is Salesforce's key for Hebrew).
const LANGUAGES = [
    { value: 'en_US', label: 'English', matches: (lang) => lang.startsWith('en') },
    { value: 'iw', label: 'עברית', matches: (lang) => lang.startsWith('iw') || lang.startsWith('he') }
];

/**
 * Switches the current user's Salesforce UI language and reloads the page, so the whole UI
 * (Salesforce menus, custom labels, right-to-left layout) changes together.
 * Fires "languagechange" just before the reload.
 */
export default class LanguageSwitcher extends LightningElement {
    labels = { LANGUAGE };
    isSwitching = false;

    get currentLanguage() {
        const lang = (LANG || '').toLowerCase();
        return LANGUAGES.find((l) => l.matches(lang))?.value;
    }

    get languages() {
        const current = this.currentLanguage;
        return LANGUAGES.map(({ value, label }) => ({ value, label, checked: value === current }));
    }

    async handleSelect(event) {
        const languageKey = event.detail.value;
        if (languageKey === this.currentLanguage) {
            return;
        }
        this.isSwitching = true;
        try {
            await setMyLanguage({ languageKey });
            // Lets the hosting component keep its state across the reload (synchronous: handlers run first).
            this.dispatchEvent(new CustomEvent('languagechange', { detail: { language: languageKey } }));
            window.location.reload();
        } catch (error) {
            this.isSwitching = false;
            // Details go to the browser console; the user gets a generic message (no internal details).
            console.error('Language change failed', error);
            this.dispatchEvent(new ShowToastEvent({ title: ERROR, message: ERROR_DETAIL, variant: 'error' }));
        }
    }
}
