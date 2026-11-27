import 'models.dart';
import 'category_entry.dart';

List<String> categoryIds(AppSettings settings, Iterable<WarrantyItem> items) => {
  ...productTypes.where((e) => e.name != 'Custom').map((e) => e.name),
  ...settings.categories.keys,
  ...items.map((e) => e.productType),
}.where((id) => !(settings.categories[id]?.deleted ?? false)).toList();

WarrantyItem normalizeItemCategory(WarrantyItem item, AppSettings settings) {
  final id = resolveCategory(item.productType, settings.categories);
  return id == item.productType ? item : WarrantyItem.fromJson({...item.toJson(), 'productType': id});
}
