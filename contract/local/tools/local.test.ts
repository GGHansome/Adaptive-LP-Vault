import assert from 'node:assert/strict';
import test from 'node:test';
import { assertLoopback } from './local.js';
test('只允许无凭据的回环 HTTP 端点', () => {
  for (const u of ['http://127.0.0.1:8545', 'http://localhost:8545', 'http://[::1]:8545'])
    assert.doesNotThrow(() => assertLoopback(u));
  for (const u of [
    'https://mainnet.example',
    'http://192.168.0.2:8545',
    'http://localhost.example:8545',
    'http://user:pass@localhost:8545',
    'http://127.0.0.1:8545/path',
  ])
    assert.throws(() => assertLoopback(u));
});
