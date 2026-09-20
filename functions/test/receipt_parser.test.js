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

test('parses a Macedonian invoice with amount due and serial number', () => {
  const parsed = parseReceipt(`
ФАКТУРА
Продавач
АЈ СТАИЛ ДООЕЛ Скопје
Датум на фактура 18.09.2026
Apple MB NEO 13 INDIGO A18 PRO 6C CPU 5C GPU 8GB 512GB
Сериски број: C4H615521AXPK84B
Износ за плаќање MKD 47480.00
`);
  assert.equal(parsed.store, 'АЈ СТАИЛ ДООЕЛ Скопје');
  assert.equal(parsed.purchaseDate, '2026-09-18');
  assert.equal(parsed.price, 47480);
  assert.equal(parsed.currency, 'MKD');
  assert.equal(parsed.serialNumber, 'C4H615521AXPK84B');
  assert.equal(parsed.brand, 'Apple');
  assert.match(parsed.productName, /Apple MB NEO 13/);
});

test('rejects impossible dates', () => {
  assert.equal(parseDate('31/02/2026'), null);
});
