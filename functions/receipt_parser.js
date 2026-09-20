'use strict';

const MONTHS = {
  jan: 1, january: 1, feb: 2, february: 2, mar: 3, march: 3,
  apr: 4, april: 4, may: 5, jun: 6, june: 6, jul: 7, july: 7,
  aug: 8, august: 8, sep: 9, sept: 9, september: 9,
  oct: 10, october: 10, nov: 11, november: 11, dec: 12, december: 12,
};

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

function parseReceipt(text) {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const totalLine = [...lines].reverse().find((line) => /\b(total|amount|вкупно|vkupno|sum|итого|totale|gesamt)\b/i.test(line));
  const moneyMatch = totalLine?.match(/(?:MKD|DEN|EUR|USD|€|\$|ден)?\s*([\d.,]+)\s*(?:MKD|DEN|EUR|USD|€|\$|ден)?/i);
  const currencySource = `${totalLine || ''} ${text}`;
  const currency = /€|\bEUR\b/i.test(currencySource) ? 'EUR'
    : /\$|\bUSD\b/i.test(currencySource) ? 'USD'
    : /\b(MKD|DEN)\b|ден/i.test(currencySource) ? 'MKD' : null;
  const store = lines.find((line) => /[A-Za-zА-Яа-я]{3}/.test(line) && !/receipt|invoice|фискал|сметка/i.test(line)) || null;
  const serialLine = lines.find((line) => /\b(serial|s\/n|sn|сериски)\b/i.test(line));
  const serialNumber = serialLine?.replace(/^.*?\b(serial(?: number)?|s\/n|sn|сериски(?: број)?)\b\s*[:#-]?\s*/i, '').trim() || null;
  return {
    store,
    purchaseDate: parseDate(text),
    price: moneyMatch ? parseMoney(moneyMatch[1]) : null,
    currency,
    serialNumber,
    rawText: text.slice(0, 12000),
  };
}

module.exports = {parseReceipt, parseDate, parseMoney};
