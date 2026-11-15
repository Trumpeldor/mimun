/**
 * Lets users switch their OWN Salesforce UI language between the languages the app is
 * translated into (used by the languageSwitcher LWC). The whole UI - Salesforce menus,
 * custom labels, right-to-left layout - follows the user's language after a page reload.
 *
 * Only the running user's record is changed, and only to a supported language.
 */
public with sharing class UserLanguageController {
    /** Languages the app is translated into (Salesforce language keys; "iw" = Hebrew). */
    @TestVisible
    private static final Set<String> SUPPORTED_LANGUAGES = new Set<String>{ 'en_US', 'iw' };

    @AuraEnabled
    public static void setMyLanguage(String languageKey) {
        if (!SUPPORTED_LANGUAGES.contains(languageKey)) {
            AuraHandledException e = new AuraHandledException('Unsupported language: ' + languageKey);
            e.setMessage('Unsupported language: ' + languageKey);
            throw e;
        }
        update new User(Id = UserInfo.getUserId(), LanguageLocaleKey = languageKey);
    }
}
