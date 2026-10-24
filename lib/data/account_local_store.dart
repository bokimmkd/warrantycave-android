import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';

typedef LocalSnapshot = (List<WarrantyItem>, AppSettings);

/// One atomic file contains separate guest/account vaults. Switching accounts
/// never deletes another account's local-only warranties or cached entitlement.
class AccountLocalStore {
  AccountLocalStore({this.directory});
  final Directory? directory;
  Future<void> _tail = Future<void>.value();
  String? _activeScope;
  Future<File> get _file async => File(
    '${(directory ?? await getApplicationDocumentsDirectory()).path}/warrantycave/data.json',
  );
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Map<String, dynamic> _encode(LocalSnapshot value) => {
    'items': value.$1.map((e) => e.toJson()).toList(),
    'settings': value.$2.toJson(),
  };
  LocalSnapshot _decode(dynamic value) {
    if (value == null) return (<WarrantyItem>[], const AppSettings());
    final root = Map<String, dynamic>.from(value as Map);
    return (
      (root['items'] as List? ?? []).map((e) => WarrantyItem.fromJson(
        Map<String, dynamic>.from(e as Map))).toList(),
      AppSettings.fromJson(Map<String, dynamic>.from(root['settings'] as Map)),
    );
  }
  AppSettings _deviceSettings(AppSettings value) => AppSettings(
    onboardingComplete: value.onboardingComplete,
    darkMode: value.darkMode,
    languageCode: value.languageCode,
    defaultCurrency: value.defaultCurrency,
    notificationConsentGranted: value.notificationConsentGranted,
    expiringThresholdDays: value.expiringThresholdDays,
    reminder60: value.reminder60, reminder30: value.reminder30,
    reminder7: value.reminder7, reminderExpiry: value.reminderExpiry,
  );

  void _validate(Map<String, dynamic> root) {
    if (root['schemaVersion'] == 3) {
      for (final value in (root['profiles'] as Map).values) { _decode(value); }
      AppSettings.fromJson(Map<String, dynamic>.from(root['device'] as Map));
      if (root['legacy'] != null) _decode(root['legacy']);
    } else { _decode(root); }
  }

  Future<Map<String, dynamic>> _read() async {
    final file = await _file;
    var existed = false;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      existed = true;
      try {
        final root = Map<String, dynamic>.from(jsonDecode(await candidate.readAsString()) as Map);
        _validate(root);
        if (root['schemaVersion'] == 3) {
          return root;
        }
        final legacy = _decode(root);
        return {
          'schemaVersion': 3, 'profiles': <String, dynamic>{},
          'device': _deviceSettings(legacy.$2).toJson(), 'legacy': root,
        };
      } catch (_) { /* Try the last complete backup; never overwrite both on corruption. */ }
    }
    if (existed) throw const FormatException('local-data-unreadable');
    return {'schemaVersion': 3, 'profiles': <String, dynamic>{},
      'device': const AppSettings().toJson()};
  }

  Future<void> _write(Map<String, dynamic> root) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(root), flush: true);
    // Preserve a valid backup even if the primary was corrupt and recovered.
    if (await file.exists()) {
      try {
        final old = Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
        _validate(old);
        await file.copy('${file.path}.bak');
      } catch (_) { /* Keep recovery backup. */ }
    }
    await temp.rename(file.path);
  }

  Future<LocalSnapshot> load() => activate(null);

  Future<LocalSnapshot> activate(String? uid, {String? email, bool claimGuest = false}) => _serial(() async {
    final root = await _read();
    final profiles = Map<String, dynamic>.from(root['profiles'] as Map);
    final scope = uid == null ? 'guest' : 'user:$uid';
    final device = AppSettings.fromJson(Map<String, dynamic>.from(root['device'] as Map));
    if (root['legacy'] != null) {
      final legacy = _decode(root['legacy']);
      final s = legacy.$2;
      String? owner;
      if (s.cloudOwnerUid.isNotEmpty) {
        owner = 'user:${s.cloudOwnerUid}';
      } else if (uid != null && (
        (s.email.isNotEmpty && s.email.toLowerCase() == (email ?? '').toLowerCase()) ||
        (s.referralCode.isNotEmpty && s.referralCode == ReferralPolicy.codeForUser(uid)) ||
        (s.email.isEmpty && s.referralCode.isEmpty))) {
        owner = scope;
      } else if (legacy.$1.isEmpty && s.email.isEmpty && s.referralCode.isEmpty) {
        owner = 'guest';
      }
      // Unidentified signed-out legacy data stays retained and hidden until
      // its owner signs in. It is never adopted by a different known account.
      if (owner != null) {
        final current = profiles.containsKey(owner) ? _decode(profiles[owner]) : null;
        profiles[owner] = current == null ? _encode(legacy) : _encode(({
          for (final item in legacy.$1) item.id: item,
          for (final item in current.$1) item.id: item,
        }.values.toList(), current.$2));
        root.remove('legacy');
      }
    }
    var target = profiles.containsKey(scope)
      ? _decode(profiles[scope]) : (<WarrantyItem>[], _deviceSettings(device));
    final guest = _decode(profiles['guest']);
    if (uid != null && claimGuest && (guest.$1.isNotEmpty || guest.$2.categories.isNotEmpty)) {
      final merged = {for (final item in guest.$1) item.id: item,
        for (final item in target.$1) item.id: item};
      target = (merged.values.toList(), target.$2.copyWith(
        categories: {...guest.$2.categories, ...target.$2.categories},
      ));
      // Transfer, rather than copy: a later account must not inherit these.
      profiles['guest'] = _encode((<WarrantyItem>[], _deviceSettings(device)));
    }
    var settings = target.$2.copyWith(
      onboardingComplete: device.onboardingComplete || target.$2.onboardingComplete,
      darkMode: device.darkMode, languageCode: device.languageCode,
      notificationConsentGranted: device.notificationConsentGranted,
      cloudOwnerUid: uid ?? '',
      email: uid == null ? '' : email ?? target.$2.email,
    );
    if (uid == null) settings = _deviceSettings(settings).copyWith(categories: settings.categories);
    target = (target.$1, settings);
    profiles[scope] = _encode(target);
    root['profiles'] = profiles;
    root['activeScope'] = scope;
    await _write(root);
    _activeScope = scope; // Change in-memory ownership only after disk commits.
    return target;
  });

  Future<void> save(List<WarrantyItem> items, AppSettings settings) {
    final scope = _activeScope;
    if (scope == null) throw StateError('local-account-not-loaded');
    final snapshot = _encode((List<WarrantyItem>.of(items), settings));
    return _serial(() async {
      final root = await _read();
      final profiles = Map<String, dynamic>.from(root['profiles'] as Map);
      profiles[scope] = snapshot;
      root['profiles'] = profiles;
      root['device'] = _deviceSettings(settings).toJson();
      await _write(root);
    });
  }

  Future<void> removeAccount(String uid) => _serial(() async {
    final root = await _read();
    (root['profiles'] as Map).remove('user:$uid');
    await _write(root);
    // Account deletion must not leave a recoverable copy in the rolling backup.
    await (await _file).copy('${(await _file).path}.bak');
  });
}
