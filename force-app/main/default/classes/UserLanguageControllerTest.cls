@IsTest
private class UserLanguageControllerTest {
    @IsTest
    static void salesRepCanSwitchOwnLanguage() {
        User rep = newPlatformUser();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert rep;
            insert new PermissionSetAssignment(
                AssigneeId = rep.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Sales_Summary_Sales_Rep'].Id
            );
        }

        System.runAs(rep) {
            UserLanguageController.setMyLanguage('iw');
        }
        Assert.areEqual('iw', [SELECT LanguageLocaleKey FROM User WHERE Id = :rep.Id].LanguageLocaleKey);

        System.runAs(rep) {
            UserLanguageController.setMyLanguage('en_US');
        }
        Assert.areEqual('en_US', [SELECT LanguageLocaleKey FROM User WHERE Id = :rep.Id].LanguageLocaleKey);
    }

    @IsTest
    static void unsupportedLanguageIsRejected() {
        String before = [SELECT LanguageLocaleKey FROM User WHERE Id = :UserInfo.getUserId()].LanguageLocaleKey;
        try {
            UserLanguageController.setMyLanguage('fr');
            Assert.fail('only supported languages may be set');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('fr'));
        }
        Assert.areEqual(before, [SELECT LanguageLocaleKey FROM User WHERE Id = :UserInfo.getUserId()].LanguageLocaleKey);
    }

    @IsTest
    static void nullLanguageIsRejected() {
        try {
            UserLanguageController.setMyLanguage(null);
            Assert.fail('null must be rejected');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    private static User newPlatformUser() {
        return new User(
            LastName = 'Language Test',
            Alias = 'langtst',
            Email = 'language.test@example.com',
            Username = 'language.test.' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(8) + '@sales-summary.test',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard Platform User' LIMIT 1].Id,
            TimeZoneSidKey = 'Asia/Jerusalem',
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
    }
}
