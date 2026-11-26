import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectx/models/user.dart';
import 'package:connectx/services/chat_storage.dart';

class ChatContactInfoScreen extends StatefulWidget {
  final User1 user;
  final Future<void> Function(String wallpaperId, String? wallpaperUrl) onWallpaperSelected;
  const ChatContactInfoScreen({super.key, required this.user, required this.onWallpaperSelected});

  @override
  State<ChatContactInfoScreen> createState() => _ChatContactInfoScreenState();
}

class _ChatContactInfoScreenState extends State<ChatContactInfoScreen> {
  static const List<Color> _wallpapers = [
    Color(0xFFEFEAE2), Color(0xFFDCEFE7), Color(0xFFE1E9F8), Color(0xFFF8E2E2),
    Color(0xFFF5E9CF), Color(0xFFE8DDF4), Color(0xFFD9E8EA), Color(0xFFF2E3D3),
    Color(0xFF24323A), Color(0xFF172B4D), Color(0xFF283A2F), Color(0xFF402D35),
    Color(0xFF3A3150), Color(0xFF263B48), Color(0xFF4A3B2D), Color(0xFF20252B),
    Color(0xFFF0F1F3), Color(0xFFE3F2FD), Color(0xFFFCE4EC), Color(0xFFE8F5E9),
  ];
  Map<String, dynamic> _profile = {};
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _profile = {
      'name': widget.user.name, 'username': widget.user.username,
      'bio': widget.user.bio, 'photoUrl': widget.user.photoUrl,
    };
  }

  Future<void> _uploadWallpaper() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
        throw Exception('Choose an image smaller than 25 MB.');
      }
      final me = FirebaseAuth.instance.currentUser!.uid;
      final ids = [me, widget.user.key]..sort();
      final url = await ChatStorage.upload(
        conversationId: ids.join(','),
        fileName: 'chat_wallpaper_${DateTime.now().millisecondsSinceEpoch}.${picked.name.split('.').last}',
        bytes: Uint8List.fromList(bytes),
        contentType: picked.mimeType ?? 'image/jpeg',
        viewOnce: false,
      );
      await widget.onWallpaperSelected('custom', url);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat wallpaper updated.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallpaper upload failed. Please try another image.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _chooseWallpaper() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .78,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                const Expanded(child: Text('Chat wallpaper', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
              ]),
            ),
            Expanded(child: GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .78,
              ),
              itemCount: _wallpapers.length,
              itemBuilder: (context, index) => InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await widget.onWallpaperSelected(index.toString(), null);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Wallpaper ${index + 1} applied to this chat.')),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _wallpapers[index],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Center(child: Icon(Icons.chat_bubble_outline_rounded,
                    size: 34, color: index >= 8 && index <= 15 ? Colors.white70 : Colors.black38)),
                ),
              ),
            )),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: _uploading ? null : () { Navigator.pop(sheetContext); _uploadWallpaper(); },
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wallpaper_outlined),
                label: const Text('Upload Wallpaper'),
              )),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact info'), actions: [
        IconButton(tooltip: 'Chat wallpaper', icon: const Icon(Icons.wallpaper_outlined), onPressed: _chooseWallpaper),
      ]),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('PublicUsers').child(widget.user.key).onValue,
        builder: (context, snapshot) {
          final raw = snapshot.data?.snapshot.value;
          if (raw is Map) {
            _profile = Map<String, dynamic>.from(raw);
          }
          final name = (_profile['name'] ?? widget.user.name).toString();
          final username = (_profile['username'] ?? widget.user.username).toString();
          final bio = (_profile['bio'] ?? _profile['about'] ?? widget.user.bio).toString();
          final photo = (_profile['photoUrl'] ?? widget.user.photoUrl).toString();
          return ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 30), children: [
            Center(child: CircleAvatar(
              radius: 58,
              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
              child: photo.isEmpty ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 38)) : null,
            )),
            const SizedBox(height: 14),
            Center(child: Text(name, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700))),
            const SizedBox(height: 4),
            Center(child: Text('@$username', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15))),
            const SizedBox(height: 24),
            Card(child: Column(children: [
              ListTile(leading: const Icon(Icons.info_outline), title: const Text('About / Bio'),
                subtitle: Text(bio.isEmpty ? 'No bio added' : bio)),
              const Divider(height: 1),
              const ListTile(leading: Icon(Icons.phone_outlined), title: Text('Phone number'),
                subtitle: Text('Private — this user has not shared a phone number publicly.')),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.alternate_email), title: const Text('Username'), subtitle: Text('@$username')),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.circle, color: Colors.green, size: 12),
                title: const Text('Status'), subtitle: Text(_profile['online'] == true ? 'Online' : 'Offline')),
            ])),
            const SizedBox(height: 18),
            Card(child: ListTile(
              leading: const Icon(Icons.wallpaper_outlined),
              title: const Text('Chat wallpaper', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('20 built-in wallpapers or upload your own'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _chooseWallpaper,
            )),
          ]);
        },
      ),
    );
  }
}
