import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/data/firebase_services.dart';
import 'package:warranty_cave/domain/models.dart';
import 'account_local_store_test.dart' show item;

void main() {
  test('unchanged cloud record skips upload; new guest record does not', () {
    final local = item('same');
    expect(warrantyNeedsUpload(local, WarrantyItem.fromJson(local.toJson())), isFalse);
    expect(warrantyNeedsUpload(local, null), isTrue);
  });
  test('edits to every serialized field still require an upload', () {
    final local = item('same');
    for (final entry in <String, dynamic>{
      'productName': 'Changed', 'notes': 'Offline note',
      'expiryDate': DateTime(2030).toIso8601String(),
      'receiptPhotos': ['https://example.test/receipt.jpg'],
      'productPhoto': '/local/new.jpg', 'reminderDays': [7],
    }.entries) {
      final remote = WarrantyItem.fromJson({...local.toJson(), entry.key: entry.value});
      expect(warrantyNeedsUpload(local, remote), isTrue, reason: entry.key);
    }
  });
  test('skipping unchanged uploads does not remove remote-only or guest warranties', () {
    final same = item('same');
    final merged = mergeAccountWarranties([same, item('guest')], [same, item('cloud'), item('deleted')], ['deleted']);
    expect(merged.map((i) => i.id), unorderedEquals(['same','guest','cloud']));
  });
}
