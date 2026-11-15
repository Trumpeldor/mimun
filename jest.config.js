const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    // Shared test data helpers (e.g. __tests__/summaryFixture.js) are not test suites.
    testPathIgnorePatterns: [...(jestConfig.testPathIgnorePatterns || ['/node_modules/']), 'Fixture\\.js$']
};
