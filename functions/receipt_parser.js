'use strict';

const MONTHS = {
  jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3,
  apr: 4, april: 4, may: 5, jun: 6, june: 6, jul: 7, july: 7,
  aug: 8, august: 8, sep: 9, sept: 9, september: 9,
  oct: 10, october: 10, nov: 11, november: 11, dec: 12, december: 12,
};

const DOCUMENT_HEADING = /^(receipt|invoice|tax invoice|фактура|сметка|фискал(?:на сметка)?|original|оригинал)$/i;
const TOTAL_LABEL = /(?:amount\s+due|grand\s+total|total\s+due|износ\s+за\s+пла[ќк]ање|за\s+пла[ќк]ање|вкупен\s+износ|вкупно|vkupno|total|amount|sum|итого|totale|gesamt)/i;
const COMPANY_SUFFIX = /(?:дооел|доо|ад|llc|ltd\.?|gmbh|srl|spa)(?:\s|$)/i;
const SERIAL_LABEL = /(?:serial(?:\s*(?:number|no\.?))?|s\s*\/\s*n|сериски\s*број|сериски)/i;
const KNOWN_BRANDS = [
  'Apple', 'Samsung', 'Sony', 'LG', 'Lenovo', 'HP', 'Dell', 'Asus', 'Acer',
  'Huawei', 'Xiaomi', 'Bosch', 'Beko', 'Gorenje', 'Philips', 'Panasonic',
  'Whirlpool', 'Electrolux', 'Hisense', 'TCL', 'Nintendo', 'Microsoft',
];

function validDate(year, month, day) {
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  const value = new Date(Date.UTC(year, month - 1, day));
  if (value.getUTCFullYear() !== year || value.getUTCMonth() !== month - 1 || value.getUTCDate() !== day) return null;
  return value.toISOString().slice(0, 10);
}

function parseDate(text) {
  const numeric = text.match(/\b(\d{1,2})[.\/-](\d{1,2})[.\/-](20\d{2})\b/);
  if (numeric) return validDate(Number(numeric[3]), Number(numeric[2]), Number(numeric[1]));
  const iso = text.match(/\b(20\d{2})[.\/-](\d{1,2})[.\/-](\d{1,2})\b/);
  if (iso) return validDate(Number(iso[1]), Number(iso[2]), Number(iso[3]));
  const named = text.match(/\b(\d{1,2})\s+([A-Za-z]{3,9})\s+(20\d{2})\b/i);
  if (named) return validDate(Number(named[3]), MONTHS[named[2].toLowerCase()] || 0, Number(named[1]));
  return null;
}

function parseMoney(value) {
  let cleaned = value.replace(/\s/g, '').replace(/[^\d.,]/g, '');
  const comma = cleaned.lastIndexOf(',');
  const dot = cleaned.lastIndexOf('.');
  const decimal = Math.max(comma, dot);
  if (decimal >= 0 && cleaned.length - decimal - 1 === 2) {
    cleaned = `${cleaned.slice(0, decimal).replace(/[.,]/g, '')}.${cleaned.slice(decimal + 1)}`;
  } else {
    cleaned = cleaned.replace(/[.,]/g, '');
  }
  const amount = Number(cleaned);
  return Number.isFinite(amount) && amount >= 0 ? amount : null;
}

function moneyValues(line) {
  const values = [];
  const pattern = /(?:MKD|DEN|EUR|USD|€|\$|ден)?\s*(\d{1,3}(?:[ .]\d{3})*(?:[.,]\d{2})|\d+[.,]\d{2}|\d+)\s*(?:MKD|DEN|EUR|USD|€|\$|ден)?/gi;
  for (const match of line.matchAll(pattern)) {
    const value = parseMoney(match[1]);
    if (value !== null) values.push(value);
  }
  return values;
}

function findPrice(lines) {
  const labelled = lines
    .map((line, index) => ({line, index}))
    .filter(({line}) => TOTAL_LABEL.test(line));
  for (const {line, index} of labelled.reverse()) {
    const sameLine = moneyValues(line);
    if (sameLine.length) return sameLine.at(-1);
    const nextValues = moneyValues(lines[index + 1] || '');
    if (nextValues.length) return nextValues.at(-1);
  }
  return null;
}

function findStore(lines) {
  const sellerIndex = lines.findIndex((line) => /^(?:seller|vendor|merchant|продавач)(?:\s|$)/i.test(line));
  if (sellerIndex >= 0) {
    const nearby = lines.slice(sellerIndex + 1, sellerIndex + 5)
      .find((line) => COMPANY_SUFFIX.test(line) || /[A-Za-zА-Яа-яЀ-ӿ]{3}/u.test(line));
    if (nearby) return nearby;
  }
  return lines.find((line) => COMPANY_SUFFIX.test(line)) ||
    lines.find((line) => /[A-Za-zА-Яа-яЀ-ӿ]{3}/u.test(line) && !DOCUMENT_HEADING.test(line)) || null;
}

function findSerial(lines) {
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!SERIAL_LABEL.test(line)) continue;
    const afterLabel = line.replace(/^.*?(?:serial(?:\s*(?:number|no\.?))?|s\s*\/\s*n|сериски\s*број|сериски)\s*[:#-]?\s*/i, '').trim();
    const candidate = afterLabel || lines[index + 1] || '';
    const token = candidate.match(/[A-Z0-9][A-Z0-9-]{5,}/i)?.[0];
    if (token) return {serialNumber: token, index};
  }
  return {serialNumber: null, index: -1};
}

function findProduct(lines, serialIndex) {
  if (serialIndex < 0) return {productName: null, brand: null, model: null};
  const candidates = lines.slice(Math.max(0, serialIndex - 3), serialIndex)
    .filter((line) => !SERIAL_LABEL.test(line) && !TOTAL_LABEL.test(line) && !DOCUMENT_HEADING.test(line))
    .filter((line) => /[A-Za-zА-Яа-яЀ-ӿ]{3}/u.test(line));
  const productName = candidates.at(-1) || null;
  if (!productName) return {productName: null, brand: null, model: null};
  const brand = KNOWN_BRANDS.find((value) => new RegExp(`\\b${value}\\b`, 'i').test(productName)) || null;
  const model = brand ? productName.replace(new RegExp(`^.*?\\b${brand}\\b\\s*`, 'i'), '').trim() || null : null;
  return {productName, brand, model};
}

function parseReceipt(text) {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const price = findPrice(lines);
  const currencySource = text;
  const currency = /€|\bEUR\b/i.test(currencySource) ? 'EUR'
    : /\$|\bUSD\b/i.test(currencySource) ? 'USD'
    : /\b(MKD|DEN)\b|ден/i.test(currencySource) ? 'MKD' : null;
  const store = findStore(lines);
  const {serialNumber, index: serialIndex} = findSerial(lines);
  const product = findProduct(lines, serialIndex);
  return {
    store,
    purchaseDate: parseDate(text),
    price,
    currency,
    serialNumber,
    ...product,
    rawText: text.slice(0, 12000),
  };
}

module.exports = {parseReceipt, parseDate, parseMoney};
