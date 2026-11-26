import 'package:connectx/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'services/notification_service.dart';
import 'services/app_preferences.dart';
import 'services/database_service.dart';
import 'services/phone_lookup_service.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({Key? key}) : super(key: key);

  @override
  AuthPageState createState() => AuthPageState();
}

class AuthPageState extends State<AuthPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
    final muted = isDark ? const Color(0xFFB7C4C9) : const Color(0xFF667781);
    final fieldFill = isDark ? const Color(0xFF202C33) : const Color(0xFFF0F2F5);
    final cardColor = isDark ? const Color(0xFF111B21) : Colors.white;
    final busy = _isLoading || _isGoogleLoading;

    InputDecoration fieldDecoration(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: muted),
      filled: true,
      fillColor: fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF008069), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
      ),
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(26, 34, 26, 38),
                decoration: const BoxDecoration(
                  color: Color(0xFF008069),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.16),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withOpacity(.22)),
                          ),
                          child: const Icon(Icons.forum_rounded, color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        const Text('ConnectX', style: TextStyle(
                          color: Colors.white, fontSize: 29, fontWeight: FontWeight.w800,
                          letterSpacing: -.7,
                        )),
                      ]),
                      const SizedBox(height: 24),
                      Text(
                        _isLogin ? 'Welcome back' : 'Join ConnectX',
                        style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _isLogin
                            ? 'Pick up where your conversations left off.'
                            : 'Create your account and connect with your people.',
                        style: TextStyle(color: Colors.white.withOpacity(.88), fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(18, 20, 18, 28),
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? .12 : .055),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isLogin ? 'Sign in to continue' : 'Your account details',
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: foreground),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isLogin ? 'Use your email and password.' : 'A few details to get you started.',
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                            const SizedBox(height: 22),
                            if (!_isLogin) ...[
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: fieldDecoration('Full name', Icons.person_outline_rounded),
                                validator: (value) => value == null || value.trim().isEmpty
                                    ? 'Please enter your name' : null,
                              ),
                              const SizedBox(height: 13),
                              TextFormField(
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: fieldDecoration('Username', Icons.alternate_email_rounded),
                                validator: validateUsername,
                              ),
                              const SizedBox(height: 13),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                decoration: fieldDecoration('Phone number with country code', Icons.phone_outlined).copyWith(
                                  hintText: '+91 98765 43210',
                                ),
                                validator: validatePhone,
                              ),
                              const SizedBox(height: 13),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              decoration: fieldDecoration('Email address', Icons.mail_outline_rounded),
                              validator: validateEmail,
                            ),
                            const SizedBox(height: 13),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: _isLogin
                                  ? const [AutofillHints.password]
                                  : const [AutofillHints.newPassword],
                              decoration: fieldDecoration('Password', Icons.lock_outline_rounded).copyWith(
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                  icon: Icon(_obscurePassword
                                      ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) return 'Please enter your password';
                                if (!_isLogin && value.length < 6) return 'Use at least 6 characters';
                                return null;
                              },
                              onFieldSubmitted: (_) => _submitEmailPassword(),
                            ),
                            if (_isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: busy ? null : _resetPassword,
                                  child: const Text('Forgot password?'),
                                ),
                              )
                            else
                              const SizedBox(height: 18),
                            const SizedBox(height: 5),
                            FilledButton(
                              onPressed: busy ? null : _submitEmailPassword,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF008069),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFF008069).withOpacity(.55),
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(width: 21, height: 21,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(_isLogin ? 'Sign in' : 'Create account',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 18),
                            Row(children: [
                              Expanded(child: Divider(color: muted.withOpacity(.35))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('OR', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                              Expanded(child: Divider(color: muted.withOpacity(.35))),
                            ]),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: busy ? null : _continueWithGoogle,
                              icon: _isGoogleLoading
                                  ? const SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('G', style: TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
                              label: const Text('Continue with Google'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: foreground,
                                minimumSize: const Size.fromHeight(52),
                                side: BorderSide(color: muted.withOpacity(.35)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Flexible(child: Text(
                                _isLogin ? "Don't have an account?" : 'Already have an account?',
                                style: TextStyle(color: muted, fontSize: 13),
                              )),
                              TextButton(
                                onPressed: busy ? null : () => setState(() {
                                  _isLogin = !_isLogin;
                                  _formKey.currentState?.reset();
                                }),
                                child: Text(_isLogin ? 'Sign up' : 'Sign in',
                                  style: const TextStyle(color: Color(0xFF008069), fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
                child: Text(
                  'ConnectX · Your conversations, together',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitEmailPassword() async {
    if (_isLoading || _isGoogleLoading) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      final UserCredential credential;
      if (_isLogin) {
        credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password)
            .timeout(const Duration(seconds: 25));
      } else {
        credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password)
            .timeout(const Duration(seconds: 25));
        try {
          await credential.user!
              .updateDisplayName(_nameController.text.trim())
              .timeout(const Duration(seconds: 10));
        } catch (error) {
          // A display-name update is profile polish, not an authentication gate.
          debugPrint('ConnectX display-name update failed: $error');
        }
      }

      // Authentication must not depend on the optional phone-index Cloud
      // Functions. Previously a lookup/registration outage signed users out
      // after Firebase had already created their account, making the next
      // signup attempt fail with email-already-in-use.
      await _ensureUserProfile(
        credential.user!,
        preferredName: _isLogin ? null : _nameController.text.trim(),
        preferredUsername: _isLogin ? null : _usernameController.text.trim(),
      );

      if (!_isLogin) {
        try {
          await PhoneLookupService.register(
            credential.user!.uid,
            _phoneController.text.trim(),
          );
        } catch (error) {
          // Keep the newly created account usable even if phone indexing is
          // unavailable or the number is already linked to another account.
          debugPrint('ConnectX optional phone registration failed: $error');
        }
      }

      await _openMain();
    } on FirebaseAuthException catch (error) {
      await _cleanupPartialSession();
      _showError(_authError(error));
    } catch (error, stackTrace) {
      debugPrint('ConnectX email authentication/profile bootstrap failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _cleanupPartialSession();
      if (error is FirebaseException) {
        final message = error.code == 'permission-denied'
            ? 'Firebase database access was denied while preparing your profile. Please contact support.'
            : error.code == 'unavailable' || error.code == 'network-request-failed'
                ? 'Network connection failed. Check your internet and try again.'
                : 'Your account was authenticated, but profile setup failed (${error.code}). Please try again.';
        _showError(message);
      } else {
        _showError('Unable to complete sign-in. Please check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    if (_isLoading || _isGoogleLoading) return;
    setState(() => _isGoogleLoading = true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 25));
      await _ensureUserProfile(userCredential.user!);
      // Phone registration is optional and must never block account access.
      await _openMain();
    } on FirebaseAuthException catch (error) {
      await _cleanupPartialSession(clearGoogle: true);
      _showError(_authError(error));
    } catch (error) {
      await _cleanupPartialSession(clearGoogle: true);
      _showError('Google sign-in could not be completed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _ensureUserProfile(User user, {String? preferredName, String? preferredUsername}) async {
    final ref = ConnectXDatabase.instance.ref('PublicUsers').child(user.uid);
    final existing = await ref.get().timeout(const Duration(seconds: 12));
    final emailPrefix = (user.email ?? 'connectx_user')
        .split('@')
        .first
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.]'), '');
    final safePrefix = emailPrefix.isEmpty ? 'connectx' : emailPrefix;
    if (existing.exists) {
      final currentData = existing.value is Map
          ? Map<dynamic, dynamic>.from(existing.value as Map)
          : <dynamic, dynamic>{};
      // Older accounts may predate the required PublicUsers schema. Repair
      // missing fields on sign-in so profile edits and presence updates pass
      // the current Realtime Database validation rules.
      final updates = <String, dynamic>{};
      if (currentData['name'] is! String || (currentData['name'] as String).trim().isEmpty) {
        updates['name'] = user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : safePrefix;
      }
      if (currentData['username'] is! String || (currentData['username'] as String).trim().isEmpty) {
        updates['username'] = '${safePrefix}_${user.uid.substring(0, user.uid.length < 8 ? user.uid.length : 8)}';
      }
      if (currentData['key'] != user.uid) updates['key'] = user.uid;
      if (currentData['online'] is! bool) updates['online'] = true;
      if (currentData['lastSeen'] is! num) updates['lastSeen'] = ServerValue.timestamp;
      if (currentData['bio'] is! String) {
        updates['bio'] = currentData['about']?.toString() ?? 'Hey there! I am using ConnectX';
      }
      if (currentData['photoUrl'] is! String) updates['photoUrl'] = user.photoURL ?? '';
      if (currentData.containsKey('about')) updates['about'] = null;
      if (updates.isNotEmpty) await ref.update(updates).timeout(const Duration(seconds: 12));
      return;
    }
    final username = (preferredUsername?.trim().isNotEmpty ?? false)
        ? preferredUsername!.trim().toLowerCase()
        : '${safePrefix}_${user.uid.substring(0, 4)}';
    final name = (preferredName?.trim().isNotEmpty ?? false)
        ? preferredName!.trim()
        : (user.displayName?.trim().isNotEmpty ?? false)
            ? user.displayName!.trim()
            : safePrefix;

    await ref.set({
      'name': name,
      'username': username,
      'key': user.uid,
      'online': true,
      'lastSeen': ServerValue.timestamp,
      'bio': 'Hey there! I am using ConnectX',
      'photoUrl': user.photoURL ?? '',
    }).timeout(const Duration(seconds: 12));
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!isEmailValid(email)) {
      _showError('Enter your email address first to reset your password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showError('Password reset email sent. Check your inbox.');
    } on FirebaseAuthException catch (error) {
      _showError(_authError(error));
    }
  }

  Future<void> _openMain() async {
    // Local preferences and push notifications are optional startup services.
    // A failure in either must not strand an authenticated user on the login page.
    try {
      await AppPreferences.load().timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('ConnectX preferences startup failed: $error');
    }
    try {
      await NotificationService.initialize().timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('ConnectX notification startup failed: $error');
    }
    currentRoute = '/main';
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  Future<void> _cleanupPartialSession({bool clearGoogle = false}) async {
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 6));
      }
    } catch (error) {
      debugPrint('ConnectX partial authentication cleanup failed: $error');
    }
    if (clearGoogle) {
      try {
        await GoogleSignIn().signOut().timeout(const Duration(seconds: 4));
      } catch (error) {
        debugPrint('ConnectX partial Google session cleanup failed: $error');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded),
        title: const Text('ConnectX'),
        content: Text(message),
        actions: [FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        )],
      ),
    );
  }

  String _authError(FirebaseAuthException error) {
    switch (error.code) {
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'account-exists-with-different-credential':
        return 'This email already uses another sign-in method. Sign in with that method first.';
      case 'network-request-failed':
      case 'network-error':
        return 'Network error. Check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is disabled in Firebase Authentication. Enable the Email/Password provider in Firebase Console.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a while and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'invalid-login-credentials':
        return 'Invalid email or password.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }
}

bool isEmailValid(String email) {
  final emailRegExp = RegExp(
      r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$');
  return emailRegExp.hasMatch(email);
}

String? validatePhone(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return 'Please enter your phone number';
  if (digits.length < 7 || digits.length > 15) return 'Enter 7–15 digits, including country code';
  return null;
}

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Please enter your email';
  if (!isEmailValid(value.trim())) return 'Please enter a valid email';
  return null;
}

String? validateUsername(String? value) {
  final username = value?.trim() ?? '';
  final regex = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.]{2,19}$');
  if (username.isEmpty) return 'Please enter a username';
  if (username.contains('..') || username.contains('__')) {
    return 'Username cannot contain consecutive periods or underscores';
  }
  if (!regex.hasMatch(username)) {
    return 'Use 3–20 characters: letters, numbers, periods or underscores. Start with a letter.';
  }
  return null;
}
