/// Per-account category metadata. Built-in IDs remain their historic English
/// keys; custom IDs never depend on the selected language or display name.
class CategoryEntry {
  const CategoryEntry({required this.name, required this.revision, this.replacement});
  final String name;
  final String revision;
  final String? replacement;
  bool get deleted => replacement != null;
  Map<String, dynamic> toJson() => {
    'name': name, 'revision': revision,
    if (replacement != null) 'replacement': replacement,
  };
  factory CategoryEntry.fromJson(Map<String, dynamic> json) => CategoryEntry(
    name: json['name'] as String? ?? '',
    revision: json['revision'] as String? ?? '',
    replacement: json['replacement'] as String?,
  );
}

Map<String, CategoryEntry> decodeCategories(dynamic value) => {
  for (final entry in (value as Map? ?? const {}).entries)
    entry.key as String: CategoryEntry.fromJson(Map<String, dynamic>.from(entry.value as Map)),
};
Map<String, dynamic> encodeCategories(Map<String, CategoryEntry> entries) =>
  entries.map((key, value) => MapEntry(key, value.toJson()));

/// Deterministic merge, including deletion tombstones. A stale/offline device
/// must not resurrect a removed category or replace newer display names.
Map<String, CategoryEntry> mergeCategories(
  Map<String, CategoryEntry> local, Map<String, CategoryEntry> remote,
) => {...local, for (final e in remote.entries)
  if (!local.containsKey(e.key) ||
      (e.value.deleted && !local[e.key]!.deleted) ||
      (e.value.deleted == local[e.key]!.deleted && e.value.revision.compareTo(local[e.key]!.revision) > 0))
    e.key: e.value,
};

String resolveCategory(String id, Map<String, CategoryEntry> entries) {
  final seen = <String>{};
  var current = id;
  while (entries[current]?.deleted ?? false) {
    // Concurrent cross-device deletions can form a cycle. Always choose the
    // same surviving built-in fallback instead of looping or losing records.
    if (!seen.add(current)) return 'Other';
    current = entries[current]!.replacement!;
  }
  return current;
}
