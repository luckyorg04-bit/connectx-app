import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'services/database_service.dart';
import 'services/profile_storage.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _photoUrl = '';
  XFile? _pickedPhoto;
  bool _removePhoto = false;

  DatabaseReference get _profileRef => ConnectXDatabase.instance
      .ref('PublicUsers').child(FirebaseAuth.instance.currentUser!.uid);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final snapshot = await _profileRef.get();
      final user = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      setState(() {
        _name.text = snapshot.child('name').value?.toString() ?? user?.displayName ?? '';
        _about.text = snapshot.child('bio').value?.toString() ??
            snapshot.child('about').value?.toString() ?? '';
        _photoUrl = snapshot.child('photoUrl').value?.toString() ?? user?.photoURL ?? '';
        _loading = false;
      });
    } catch (error) {
      debugPrint('ConnectX edit profile load failed: $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1400,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedPhoto = picked;
      _removePhoto = false;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter your display name before saving.');
      return;
    }
    setState(() => _saving = true);
    String uploadedUrl = '';
    try {
      var nextPhotoUrl = _photoUrl;
      if (_pickedPhoto != null) {
        uploadedUrl = await ProfileStorage.upload(_pickedPhoto!);
        nextPhotoUrl = uploadedUrl;
      } else if (_removePhoto) {
        nextPhotoUrl = '';
      }

      await _profileRef.update({
        'name': name,
        'bio': _about.text.trim(),
        'photoUrl': nextPhotoUrl,
      });

      // RTDB profile is authoritative. Auth metadata is a best-effort mirror.
      try {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(
          nextPhotoUrl.isEmpty ? null : nextPhotoUrl,
        );
      } catch (error) {
        debugPrint('ConnectX Auth metadata sync failed: $error');
      }

      final oldPhoto = _photoUrl;
      if (oldPhoto.isNotEmpty && oldPhoto != nextPhotoUrl) {
        try {
          await ProfileStorage.delete(oldPhoto);
        } catch (error) {
          debugPrint('ConnectX old profile photo cleanup failed: $error');
        }
      }
      if (!mounted) return;
      setState(() {
        _photoUrl = nextPhotoUrl;
        _pickedPhoto = null;
        _removePhoto = false;
        _saving = false;
      });
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF008069), size: 42),
          title: Text(uploadedUrl.isNotEmpty
              ? 'Profile photo uploaded successfully'
              : 'Profile updated successfully'),
          content: const Text('Your profile details and photo have been saved.'),
          actions: [FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          )],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      debugPrint('ConnectX profile save failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(_pickedPhoto != null
          ? 'Profile photo could not be uploaded. Check your connection and try again.'
          : 'Profile changes could not be saved. Please try again.');
    }
  }

  void _showMessage(String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.info_outline_rounded),
        title: const Text('Profile'),
        content: Text(message),
        actions: [FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        )],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoProvider = _pickedPhoto != null
        ? FileImage(File(_pickedPhoto!.path)) as ImageProvider<Object>
        : (!_removePhoto && _photoUrl.isNotEmpty
            ? NetworkImage(_photoUrl) as ImageProvider<Object>
            : null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _saving,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                children: [
                  Center(child: Column(children: [
                    Stack(children: [
                      CircleAvatar(
                        radius: 58,
                        backgroundImage: photoProvider,
                        child: photoProvider == null
                            ? const Icon(Icons.person, size: 54)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: IconButton.filled(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.camera_alt_rounded),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _pickPhoto,
                      child: const Text('Change profile photo'),
                    ),
                    if (_photoUrl.isNotEmpty || _pickedPhoto != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _pickedPhoto = null;
                          _removePhoto = true;
                        }),
                        child: const Text('Remove photo'),
                      ),
                  ])),
                  const SizedBox(height: 26),
                  Text('YOUR NAME', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _name,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline),
                      hintText: 'Your name',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('ABOUT', style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _about,
                    maxLength: 160,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.info_outline),
                      hintText: 'Tell people a little about yourself',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alternate_email_rounded),
                    title: const Text('Email address'),
                    subtitle: Text(user?.email ?? 'Not available'),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline_rounded),
                    title: Text('Your phone number stays private'),
                    subtitle: Text('ConnectX does not publish your private phone number on your profile.'),
                  ),
                  if (_saving) const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: LinearProgressIndicator(),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _loading ? null : SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save changes'),
        ),
      ),
    );
  }
}
