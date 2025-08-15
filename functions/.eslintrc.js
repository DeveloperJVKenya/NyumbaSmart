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
  },
  settings: { // ADD THIS
    'import/resolver': {
      node: {
        paths: ['/Users/Administrator/PROJECTFlutter/JVA Projects/cmms/functions/node_modules'],
      },
    },
  },
};
