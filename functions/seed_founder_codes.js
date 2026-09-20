'use strict';
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const codes = require('./founder_codes.seed.json');

initializeApp();
const db = getFirestore();

async function main() {
  const batch = db.batch();
  for (const code of codes) {
    const {id, ...data} = code;
    batch.set(db.collection('founderCodes').doc(id), {
      ...data,
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await batch.commit();
  console.log(`Seeded ${codes.length} founder codes.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
