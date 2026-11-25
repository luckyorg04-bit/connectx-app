import 'package:connectx/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'services/notification_service.dart';
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.forum_rounded, color: Colors.white, size: 42),
                    ),
                    const SizedBox(height: 24),
                    Text('ConnectX',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            )),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin ? 'Connect with people who matter.' : 'Create your ConnectX account.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 30),
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'Please enter your name'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: validateUsername,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Phone number (include country code)',
                          hintText: '+91 98765 43210',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: validatePhone,
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: validateEmail,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Please enter your password';
                        if (!_isLogin && value.length < 6) return 'Password must be at least 6 characters';
                        return null;
                      },
                      onFieldSubmitted: (_) => _submitEmailPassword(),
                    ),
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading || _isGoogleLoading ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      )
                    else
                      const SizedBox(height: 18),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _isLoading || _isGoogleLoading ? null : _submitEmailPassword,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isLogin ? 'Login' : 'Create account'),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: Divider(color: colors.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text('OR', style: TextStyle(color: colors.onSurfaceVariant)),
                      ),
                      Expanded(child: Divider(color: colors.outlineVariant)),
                    ]),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _isLoading || _isGoogleLoading ? null : _continueWithGoogle,
                      icon: _isGoogleLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('G', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextButton(
                      onPressed: _isLoading || _isGoogleLoading
                          ? null
                          : () => setState(() {
                                _isLogin = !_isLogin;
                                _formKey.currentState?.reset();
                              }),
                      child: Text(_isLogin ? "Don't have an account? Sign up" : 'Already have an account? Login'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'By continuing, you agree to use ConnectX responsibly.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitEmailPassword() async {
    if (_isLoading || _isGoogleLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      UserCredential credential;
      if (_isLogin) {
        credential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      } else {
        final existingPhoneUid = await PhoneLookupService.findUid(_phoneController.text.trim());
        if (existingPhoneUid != null) {
          _showError('This phone number is already linked to a ConnectX account.');
          return;
        }
        credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
        await credential.user?.updateDisplayName(_nameController.text.trim());
      }
      await _ensureUserProfile(
        credential.user!,
        preferredName: _isLogin ? null : _nameController.text.trim(),
        preferredUsername: _isLogin ? null : _usernameController.text.trim(),
      );
      if (!_isLogin) {
        await PhoneLookupService.register(credential.user!.uid, _phoneController.text.trim());
      } else if (await PhoneLookupService.getPrivatePhone(credential.user!.uid) == null) {
        final phone = await _askPhoneNumber();
        if (phone == null) {
          await FirebaseAuth.instance.signOut();
          return;
        }
        await PhoneLookupService.register(credential.user!.uid, phone);
      }
      await _openMain();
    } on FirebaseAuthException catch (error) {
      _showError(_authError(error));
    } catch (error) {
      _showError('Unable to sign in right now. Please try again. $error');
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
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      await _ensureUserProfile(userCredential.user!);
      if (await PhoneLookupService.getPrivatePhone(userCredential.user!.uid) == null) {
        final phone = await _askPhoneNumber();
        if (phone == null) {
          await FirebaseAuth.instance.signOut();
          return;
        }
        await PhoneLookupService.register(userCredential.user!.uid, phone);
      }
      await _openMain();
    } on FirebaseAuthException catch (error) {
      _showError(_authError(error));
    } catch (error) {
      _showError('Google sign-in failed. Check your internet and try again. $error');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _ensureUserProfile(User user, {String? preferredName, String? preferredUsername}) async {
    final ref = ConnectXDatabase.instance.ref('PublicUsers').child(user.uid);
    final existing = await ref.get();
    if (existing.exists) {
      final currentData = existing.value is Map
          ? Map<dynamic, dynamic>.from(existing.value as Map)
          : <dynamic, dynamic>{};
      if (currentData['bio'] == null || currentData.containsKey('about')) {
        await ref.update({
          'bio': currentData['bio']?.toString() ??
              currentData['about']?.toString() ?? 'Hey there! I am using ConnectX',
          'about': null,
        });
      }
      return;
    }

    final emailPrefix = (user.email ?? 'connectx_user')
        .split('@')
        .first
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.]'), '');
    final safePrefix = emailPrefix.isEmpty ? 'connectx' : emailPrefix;
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
    });
  }

  Future<String?> _askPhoneNumber() async {
    final controller = TextEditingController();
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add your phone number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Use your phone number so people can find you on ConnectX. No OTP is required.'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '+91 98765 43210',
                  labelText: 'Phone number',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final validation = validatePhone(controller.text);
                if (validation != null) {
                  setDialogState(() => errorText = validation);
                } else {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
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
    await NotificationService.initialize();
    currentRoute = '/main';
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
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
        return 'Network error. Check your internet connection.';
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
