import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warranty_cave/data/firebase_services.dart';
import 'package:warranty_cave/data/usage_analytics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed account creation and existing password login never emit sign_up',
    () async {
      final analytics = _Analytics();
      final auth = _Auth()..failCreate = true;
      final service = FirebaseAccountService(auth: auth, analytics: analytics);
      await expectLater(
        service.createAccount(
          email: 'test@example.com',
          password: 'test-password',
          displayName: 'Test',
        ),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(analytics.methods, isEmpty);
      await service.signIn('test@example.com', 'test-password');
      expect(analytics.methods, isEmpty);
    },
  );
  test('counts the new Firebase account even if subsequent verification delivery fails', () async {
    final analytics = _Analytics();
    final auth = _Auth();
    final service = FirebaseAccountService(auth: auth, analytics: analytics);
    auth.user.failVerification = true;
    await expectLater(
      service.createAccount(
        email: 'test@example.com',
        password: 'test-password',
        displayName: 'Test',
      ),
      throwsStateError,
    );
    expect(analytics.methods, ['password']);
    await service.signIn('test@example.com', 'test-password');
    expect(analytics.methods, ['password']);
  });
}

class _Analytics extends UsageAnalytics {
  final methods = <String>[];
  @override
  Future<void> signUp(String method) async {
    methods.add(method);
  }
}

class _Auth extends Fake implements FirebaseAuth {
  final user = _User();
  bool failCreate = false;
  @override
  User? get currentUser => user;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (failCreate) throw FirebaseAuthException(code: 'email-already-in-use');
    return _Credential(user);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async => _Credential(user);
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.value);
  final User value;
  @override
  User get user => value;
}

class _User extends Fake implements User {
  bool failVerification = false;
  @override
  Future<void> updateDisplayName(String? displayName) async {}
  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    if (failVerification) throw StateError('verification unavailable');
  }

  @override
  Future<void> reload() async {}
}
