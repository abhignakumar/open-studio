import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { defineConfig } from 'eslint/config';
import importX from 'eslint-plugin-import-x';
import tseslint from '@electron-toolkit/eslint-config-ts';
import eslintConfigPrettier from 'eslint-config-prettier';
import eslintPluginReact from 'eslint-plugin-react';
import eslintPluginReactHooks from 'eslint-plugin-react-hooks';
import eslintPluginReactRefresh from 'eslint-plugin-react-refresh';
import unusedImports from 'eslint-plugin-unused-imports';
import globals from 'globals';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const sourceFiles = ['src/**/*.{ts,tsx}', 'electron.vite.config.ts'];
const rendererFiles = ['src/renderer/src/**/*.{ts,tsx}'];
const mainFiles = ['src/main/**/*.ts'];
const preloadFiles = ['src/preload/**/*.ts'];
const nodeFiles = [...mainFiles, ...preloadFiles, 'electron.vite.config.ts'];

export default defineConfig(
  {
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/out/**',
      '**/build/**',
      '**/coverage/**',
      '**/.eslintcache',
    ],
  },
  {
    files: sourceFiles,
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: __dirname,
      },
    },
    plugins: {
      'import-x': importX,
      'react-hooks': eslintPluginReactHooks,
      'react-refresh': eslintPluginReactRefresh,
      'unused-imports': unusedImports,
    },
    settings: {
      'import-x/resolver-next': [
        importX.createNodeResolver({
          extensions: ['.js', '.jsx', '.ts', '.tsx', '.d.ts'],
        }),
      ],
    },
    rules: {
      '@typescript-eslint/array-type': ['error', { default: 'array-simple' }],
      '@typescript-eslint/consistent-type-imports': [
        'error',
        { prefer: 'type-imports', fixStyle: 'separate-type-imports' },
      ],
      '@typescript-eslint/no-confusing-void-expression': [
        'error',
        { ignoreArrowShorthand: true, ignoreVoidOperator: true },
      ],
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': [
        'error',
        { checksVoidReturn: { attributes: false } },
      ],
      '@typescript-eslint/no-unnecessary-condition': 'warn',
      '@typescript-eslint/no-unused-vars': 'off',
      '@typescript-eslint/prefer-nullish-coalescing': 'warn',
      '@typescript-eslint/require-await': 'error',
      '@typescript-eslint/restrict-template-expressions': [
        'error',
        { allowBoolean: true, allowNever: true, allowNullish: true, allowNumber: true },
      ],
      'import-x/consistent-type-specifier-style': ['error', 'prefer-top-level'],
      'import-x/first': 'error',
      'import-x/newline-after-import': 'error',
      'import-x/no-absolute-path': 'error',
      'import-x/no-duplicates': 'error',
      'import-x/no-mutable-exports': 'error',
      'import-x/no-self-import': 'error',
      'import-x/no-unresolved': ['error', { ignore: ['\\?asset$'] }],
      'import-x/no-useless-path-segments': ['error', { noUselessIndex: true }],
      'import-x/order': [
        'error',
        {
          groups: [
            'builtin',
            'external',
            'internal',
            ['parent', 'sibling', 'index'],
            'object',
            'type',
          ],
          'newlines-between': 'always',
          alphabetize: { order: 'asc', caseInsensitive: true },
          pathGroups: [
            {
              pattern: '@renderer/**',
              group: 'internal',
              position: 'before',
            },
          ],
          pathGroupsExcludedImportTypes: ['builtin'],
        },
      ],
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-restricted-syntax': [
        'error',
        {
          selector: 'TSEnumDeclaration:not([const=true])',
          message: 'Use union types or const enums instead of runtime enums.',
        },
      ],
      'unused-imports/no-unused-imports': 'error',
      'unused-imports/no-unused-vars': [
        'warn',
        {
          args: 'after-used',
          argsIgnorePattern: '^_',
          vars: 'all',
          varsIgnorePattern: '^_',
        },
      ],
    },
  },
  ...tseslint.configs.recommendedTypeChecked.map((config) => ({
    ...config,
    files: sourceFiles,
  })),
  {
    ...importX.flatConfigs.recommended,
    files: sourceFiles,
  },
  {
    files: rendererFiles,
    ...eslintPluginReact.configs.flat.recommended,
    ...eslintPluginReact.configs.flat['jsx-runtime'],
    languageOptions: {
      ...eslintPluginReact.configs.flat.recommended.languageOptions,
      globals: {
        ...globals.browser,
        ...globals.es2022,
      },
    },
    settings: {
      react: {
        version: 'detect',
      },
    },
    rules: {
      ...eslintPluginReact.configs.flat.recommended.rules,
      ...eslintPluginReact.configs.flat['jsx-runtime'].rules,
      ...eslintPluginReactHooks.configs.recommended.rules,
      ...eslintPluginReactRefresh.configs.vite.rules,
      'import-x/no-nodejs-modules': 'error',
      'react/prop-types': 'off',
    },
  },
  {
    files: nodeFiles,
    languageOptions: {
      globals: {
        ...globals.node,
        ...globals.es2022,
      },
    },
    rules: {
      'import-x/no-nodejs-modules': 'off',
      'no-console': 'off',
    },
  },
  {
    files: preloadFiles,
    rules: {
      'no-restricted-imports': [
        'error',
        {
          paths: [
            {
              name: 'fs',
              message:
                'Keep preload narrow; expose explicit main-process APIs instead of filesystem access.',
            },
            {
              name: 'node:fs',
              message:
                'Keep preload narrow; expose explicit main-process APIs instead of filesystem access.',
            },
            {
              name: 'child_process',
              message: 'Preload must not spawn processes; route native work through Electron main.',
            },
            {
              name: 'node:child_process',
              message: 'Preload must not spawn processes; route native work through Electron main.',
            },
          ],
        },
      ],
    },
  },
  {
    files: ['*.config.{js,mjs,ts}', 'eslint.config.mjs'],
    rules: {
      'import-x/no-unresolved': 'off',
      '@typescript-eslint/no-var-requires': 'off',
    },
  },
  eslintConfigPrettier,
);
