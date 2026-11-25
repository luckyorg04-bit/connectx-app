import 'package:connectx/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({Key? key}) : super(key: key);
  @override
  AuthPageState createState() => AuthPageState();
}

class AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isLogin = true, _isLoading = false, _isGoogleLoading = false;
  bool _isResetting = false, _obscurePassword = true;
  bool get _busy => _isLoading || _isGoogleLoading || _isResetting;

  @override
  void dispose() {
    _emailController.dispose(); _passwordController.dispose();
    _nameController.dispose(); _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF10272B), Color(0xFF111B21)]
                : const [Color(0xFFE7F8F6), Color(0xFFF8FAFC), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF12B8B0), Color(0xFF087F83)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [BoxShadow(color: const Color(0xFF087F83).withOpacity(.22), blurRadius: 24, offset: const Offset(0, 10))],
                      ),
                      child: const Icon(Icons.forum_rounded, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 17),
                    Text('ConnectX', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.7, color: dark ? Colors.white : const Color(0xFF12383A))),
                    const SizedBox(height: 6),
                    Text('Your conversations, all in one place.', style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: colors.outlineVariant.withOpacity(.6)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(dark ? .12 : .05), blurRadius: 30, offset: const Offset(0, 12))],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: colors.surfaceContainerHighest.withOpacity(.65), borderRadius: BorderRadius.circular(14)),
                              child: Row(children: [
                                _tab('Sign in', true, colors),
                                _tab('Create account', false, colors),
                              ]),
                            ),
                            const SizedBox(height: 23),
                            Text(_isLogin ? 'Welcome back' : 'Join ConnectX', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Text(_isLogin ? 'Sign in to continue to your account.' : 'Create your account to get started.', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                            const SizedBox(height: 20),
                            if (!_isLogin) ...[
                              _textField(_nameController, 'Full name', Icons.person_outline, validator: (v) => v == null || v.trim().length < 2 ? 'Enter your full name' : null, capitalization: TextCapitalization.words),
                              const SizedBox(height: 13),
                              _textField(_usernameController, 'Username', Icons.alternate_email, validator: validateUsername, autocorrect: false),
                              const SizedBox(height: 13),
                            ],
                            _textField(_emailController, 'Email address', Icons.mail_outline, validator: validateEmail, keyboard: TextInputType.emailAddress, autocorrect: false),
                            const SizedBox(height: 13),
                            TextFormField(
                              controller: _passwordController, obscureText: _obscurePassword,
                              autocorrect: false, enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              decoration: _decoration('Password', Icons.lock_outline, colors).copyWith(
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Enter your password';
                                if (!_isLogin && v.length < 8) return 'Use at least 8 characters';
                                return null;
                              },
                              onFieldSubmitted: (_) => _submitEmailPassword(),
                            ),
                            if (_isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('Forgot password?')),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text('Use at least 8 characters for a stronger password.', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                              ),
                            const SizedBox(height: 10),
                            FilledButton(
                              onPressed: _busy ? null : _submitEmailPassword,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                                backgroundColor: const Color(0xFF087F83), foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                              child: _isLoading ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(_isLogin ? 'Sign in' : 'Create account', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 19),
                            Row(children: [
                              Expanded(child: Divider(color: colors.outlineVariant)),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('OR CONTINUE WITH', style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant, letterSpacing: .7))),
                              Expanded(child: Divider(color: colors.outlineVariant)),
                            ]),
                            const SizedBox(height: 17),
                            OutlinedButton(
                              onPressed: _busy ? null : _continueWithGoogle,
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: BorderSide(color: colors.outlineVariant), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                if (_isGoogleLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                else const Text('G', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
                                const SizedBox(width: 10),
                                const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('By continuing, you agree to use ConnectX responsibly.', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, bool loginTab, ColorScheme colors) {
    final selected = _isLogin == loginTab;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: _busy || selected ? null : () => setState(() { _isLogin = loginTab; _formKey.currentState?.reset(); _passwordController.clear(); }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: selected ? colors.surface : Colors.transparent, borderRadius: BorderRadius.circular(11)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? colors.primary : colors.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label, IconData icon, {
    required String? Function(String?) validator,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    bool autocorrect = true,
  }) => TextFormField(
    controller: controller, keyboardType: keyboard, textCapitalization: capitalization,
    textInputAction: TextInputAction.next, autocorrect: autocorrect, enableSuggestions: autocorrect,
    decoration: _decoration(label, icon, Theme.of(context).colorScheme), validator: validator,
  );

  InputDecoration _decoration(String label, IconData icon, ColorScheme colors) => InputDecoration(
    labelText: label, prefixIcon: Icon(icon, color: colors.onSurfaceVariant),
    filled: true, fillColor: colors.surfaceContainerHighest.withOpacity(.38),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.outlineVariant)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.outlineVariant)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF0AA5A8), width: 1.6)),
  );

  Future<void> _submitEmailPassword() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;
      UserCredential credential;
      if (_isLogin) {
        credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        await _ensureUserProfile(credential.user!);
      } else {
        credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
        try {
          await credential.user!.updateDisplayName(_nameController.text.trim());
          await _ensureUserProfile(credential.user!, preferredName: _nameController.text.trim(), preferredUsername: _usernameController.text.trim().toLowerCase(), requirePreferredUsername: true);
        } catch (_) {
          try { await credential.user!.delete(); } catch (_) { await FirebaseAuth.instance.signOut(); }
          rethrow;
        }
      }
      await _openMain();
    } on FirebaseAuthException catch (e) {
      _showError(_authError(e));
    } on UsernameTakenException {
      _showError('That username is already taken. Choose another one.');
    } catch (e) {
      debugPrint('ConnectX auth/profile error: $e');
      _showError('We could not complete this request. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    if (_busy) return;
    setState(() => _isGoogleLoading = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) throw Exception('Missing Google ID token');
      final credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      await _ensureUserProfile(result.user!);
      await _openMain();
    } on FirebaseAuthException catch (e) {
      _showError(_authError(e));
    } catch (e) {
      debugPrint('ConnectX Google auth error: $e');
      _showError('Google sign-in could not be completed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _ensureUserProfile(User user, {String? preferredName, String? preferredUsername, bool requirePreferredUsername = false}) async {
    final users = ConnectXDatabase.instance.ref('PublicUsers');
    final userRef = users.child(user.uid);
    final existing = await userRef.get();
    if (existing.exists) {
      final data = existing.value is Map ? Map<dynamic, dynamic>.from(existing.value as Map) : <dynamic, dynamic>{};
      if (data['bio'] == null || data.containsKey('about')) {
        await userRef.update({'bio': data['bio']?.toString() ?? data['about']?.toString() ?? 'Hey there! I am using ConnectX', 'about': null});
      }
      return;
    }

    final prefix = (user.email ?? 'connectx_user').split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '');
    final safePrefix = prefix.isEmpty ? 'connectx' : prefix;
    final name = (preferredName?.trim().isNotEmpty ?? false) ? preferredName!.trim()
        : (user.displayName?.trim().isNotEmpty ?? false) ? user.displayName!.trim() : safePrefix;
    final username = requirePreferredUsername
        ? preferredUsername!.trim().toLowerCase()
        : await _reserveGeneratedUsername('${safePrefix}_${user.uid.substring(0, 4)}', user.uid);
    if (requirePreferredUsername) await _reserveUsername(username, user.uid);

    try {
      await userRef.set({
        'name': name, 'username': username, 'key': user.uid, 'online': true,
        'lastSeen': ServerValue.timestamp, 'bio': 'Hey there! I am using ConnectX',
        'photoUrl': user.photoURL ?? '',
      });
    } catch (_) {
      await _releaseUsername(username, user.uid);
      rethrow;
    }
  }

  Future<String> _reserveGeneratedUsername(String base, String uid) async {
    for (var i = 0; i < 8; i++) {
      final candidate = i == 0 ? base : '${base}_${i + 1}';
      try { await _reserveUsername(candidate, uid); return candidate; }
      on UsernameTakenException { continue; }
    }
    throw Exception('Could not allocate a username.');
  }

  Future<void> _reserveUsername(String username, String uid) async {
    final legacy = await ConnectXDatabase.instance.ref('PublicUsers').orderByChild('username').equalTo(username).get();
    if (legacy.children.any((child) => child.key != uid)) throw UsernameTakenException();
    final result = await ConnectXDatabase.instance.ref('UsernameIndex').child(username.replaceAll('.', ',')).runTransaction((Object? currentValue) {
      if (currentValue == null || currentValue == uid) {
        return Transaction.success(uid);
      }
      return Transaction.abort();
    }, applyLocally: false);
    if (!result.committed) throw UsernameTakenException();
  }

  Future<void> _releaseUsername(String username, String uid) async {
    try {
      await ConnectXDatabase.instance.ref('UsernameIndex').child(username.replaceAll('.', ',')).runTransaction((Object? currentValue) {
        if (currentValue == uid) return Transaction.success(null);
        return Transaction.abort();
      }, applyLocally: false);
    } catch (e) { debugPrint('ConnectX username reservation cleanup failed: $e'); }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!isEmailValid(email)) { _showError('Enter your valid email address first.'); return; }
    setState(() => _isResetting = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('If an account exists for this email, a reset link has been sent.');
    } on FirebaseAuthException catch (e) { _showError(_authError(e)); }
    catch (e) { debugPrint('ConnectX reset error: $e'); _showError('Password reset failed. Please try again.'); }
    finally { if (mounted) setState(() => _isResetting = false); }
  }

  Future<void> _openMain() async {
    await NotificationService.initialize();
    currentRoute = '/main';
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, backgroundColor: Theme.of(context).colorScheme.error));
  }
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  String _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password': return 'Password is too weak. Use at least 8 characters.';
      case 'email-already-in-use': return 'An account already exists with this email. Sign in instead.';
      case 'user-not-found': case 'wrong-password': case 'invalid-credential': return 'Email or password is incorrect.';
      case 'invalid-email': return 'Please enter a valid email address.';
      case 'account-exists-with-different-credential': return 'This email uses another sign-in method. Try that method.';
      case 'network-request-failed': return 'Network error. Check your internet connection.';
      case 'too-many-requests': return 'Too many attempts. Wait and try again.';
      case 'user-disabled': return 'This account has been disabled. Contact support.';
      case 'operation-not-allowed': return 'This sign-in method is currently unavailable.';
      default: return 'Authentication failed (${e.code}). Please try again.';
    }
  }
}

class UsernameTakenException implements Exception {}

bool isEmailValid(String email) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}
String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Please enter your email';
  if (!isEmailValid(value.trim())) return 'Please enter a valid email';
  return null;
}
String? validateUsername(String? value) {
  final username = value?.trim() ?? '';
  if (username.isEmpty) return 'Please enter a username';
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]{2,19}$').hasMatch(username) ||
      username.contains('..') || username.contains('__') ||
      username.endsWith('.') || username.endsWith('_')) {
    return 'Use 3–20 characters; start with a letter and avoid repeated separators.';
  }
  return null;
}
