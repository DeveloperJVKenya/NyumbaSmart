const path = require('path');

module.exports = {
  env: {
    node: true,
    es2021: true,
  },
  extends: ['eslint:recommended', 'airbnb-base'],
  plugins: ['import'],
  parserOptions: {
    ecmaVersion: 2021,
    sourceType: 'commonjs',
  },
  rules: {
    'no-console': 'off', // Allow console.log
    'no-await-in-loop': 'off', // Allow await in loops for this project
    'no-restricted-syntax': ['error', 'ForInStatement', 'LabeledStatement', 'WithStatement'],
    quotes: ['error', 'single'], // Enforce single quotes
    'object-curly-spacing': ['error', 'always'],
    'max-len': ['error', { code: 120 }], // Increased line length
    'eol-last': ['error', 'always'],
    'quote-props': ['off'],
    'comma-dangle': ['error', 'always-multiline'],
    semi: ['error', 'always'],
    indent: ['error', 2],
    // This checkout is on Windows, where git checks files out with CRLF line endings;
    // enforcing 'unix' linebreaks here just fights the platform for no benefit.
    'linebreak-style': 'off',
    // eslint-import-resolver-node@0.3.x doesn't understand package.json "exports" maps, so it
    // false-positives on legitimate, working subpath imports like 'firebase-admin/firestore'
    // and 'firebase-functions/v2/https'. No resolver upgrade currently fixes this; disable.
    'import/no-unresolved': 'off',
  },
  settings: {
    'import/resolver': {
      node: {
        // Resolve relative to this config file so it works on any machine/OS, instead of
        // a hardcoded absolute path (previously a macOS-only path that broke on Windows).
        paths: [path.join(__dirname, 'node_modules')],
      },
    },
  },
};
