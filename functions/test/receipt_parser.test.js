'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {parseReceipt, parseDate} = require('../receipt_parser');

test('parses Macedonian receipt total and date', () => {
  const parsed = parseReceipt('NEPTUN\nDatum 20.09.2026\nVkupno 12.499,00 MKD');
  assert.equal(parsed.store, 'NEPTUN');
  assert.equal(parsed.purchaseDate, '2026-09-20');
  assert.equal(parsed.currency, 'MKD');
  assert.equal(parsed.price, 12499);
});

test('rejects impossible dates', () => {
  assert.equal(parseDate('31/02/2026'), null);
});
