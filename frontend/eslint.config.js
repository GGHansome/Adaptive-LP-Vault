import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import globals from 'globals';
import hooks from 'eslint-plugin-react-hooks';
const networkRestriction = {
  selector: 'CallExpression[callee.name=/^(fetch|XMLHttpRequest|WebSocket|EventSource)$/]',
  message: '外部访问应放在 server-store 或 shared/web3 边界。',
};
const contractRestriction = {
  selector:
    'CallExpression[callee.type="MemberExpression"][callee.property.name=/^(readContract|simulateContract|writeContract|getLogs|getBlock|getBlockNumber|waitForTransactionReceipt)$/]',
  message: '容器只组合数据与动作，合约读写必须留在 server-store。',
};
export default tseslint.config(
  { ignores: ['dist/**', 'src/generated/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
    plugins: { 'react-hooks': hooks },
    rules: {
      ...hooks.configs.recommended.rules,
      'react-hooks/set-state-in-effect': 'off',
      'react-hooks/refs': 'off',
    },
  },
  {
    files: [
      'src/shared/components/**/*.{ts,tsx}',
      'src/features/components/**/*.{ts,tsx}',
      'src/shared/utils/**/*.{ts,tsx}',
      'src/features/utils/**/*.{ts,tsx}',
    ],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: [
                'wagmi',
                'wagmi/*',
                '@tanstack/react-query',
                'zustand',
                'zustand/*',
                'viem',
                'viem/*',
                'axios',
                '**/containers/**',
                '**/server-store/**',
                '**/store/**',
                '**/web3/**',
                '**/generated/**',
                '**/contracts',
                '**/contracts/**',
              ],
              message: '展示组件与纯函数只依赖 Props、类型及纯计算。',
            },
            {
              group: ['**/config/**'],
              allowTypeImports: true,
              message: '展示层不能读取运行配置。',
            },
          ],
        },
      ],
      'no-restricted-syntax': ['error', networkRestriction, contractRestriction],
    },
  },
  {
    files: ['src/shared/**/*.{ts,tsx}'],
    rules: {
      'no-restricted-imports': [
        'error',
        { patterns: [{ group: ['**/features/**'], message: '公共层不能反向依赖业务功能。' }] },
      ],
    },
  },
  {
    files: ['src/shared/components/**/*.{ts,tsx}', 'src/shared/utils/**/*.{ts,tsx}'],
    // Combine both restrictions rather than overriding the shared-layer rule above.
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            'wagmi',
            'wagmi/*',
            '@tanstack/react-query',
            'zustand',
            'zustand/*',
            'viem',
            'viem/*',
            'axios',
            '**/features/**',
            '**/containers/**',
            '**/server-store/**',
            '**/store/**',
            '**/web3/**',
            '**/generated/**',
            '**/config/**',
            '**/contracts',
            '**/contracts/**',
          ],
        },
      ],
    },
  },
  {
    files: ['src/features/containers/**/*.{ts,tsx}'],
    ignores: ['src/features/containers/**/server-store/**', '**/*.test.*'],
    rules: { 'no-restricted-syntax': ['error', networkRestriction, contractRestriction] },
  },
  {
    files: [
      'src/config/**/*.{ts,tsx}',
      'src/main.tsx',
      'src/App.tsx',
      'src/providers/**/*.{ts,tsx}',
    ],
    rules: { 'no-restricted-syntax': ['error', networkRestriction, contractRestriction] },
  },
);
