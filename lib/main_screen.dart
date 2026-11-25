import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/chat_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectx/models/chat.dart';
import 'package:connectx/utils/user_list.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'main.dart';
import 'app_navigator.dart';
import 'models/user.dart';
import 'profile_screen.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'services/profile_storage.dart';

List<User1> users = [];
List<Chat> chats = [];
List<StreamSubscription> subscriptions = [];
final userListKey = GlobalKey<UserListState>();

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  int _selectedTab = 0;
  late final TabController _tabController;
  bool _showProfile = false;
  String _chatFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted && _selectedTab != _tabController.index) {
        setState(() => _selectedTab = _tabController.index);
      }
    });
    WidgetsBinding.instance.addObserver(this);
    // These lists are process-wide; clear stale data and listeners when a
    // different authenticated session opens the main screen.
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    subscriptions.clear();
    users.clear();
    chats.clear();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = ConnectXDatabase.instance.ref("PublicUsers").child(uid);
    userRef.onDisconnect().update({
      'online': false,
      'lastSeen': ServerValue.timestamp,
    });
    userRef.update({'online': true});
    getData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = pendingCallArguments;
      if (pending != null) {
        pendingCallArguments = null;
        appNavigatorKey.currentState?.pushNamed(
          pending['isGroupCall'] == true ? '/group-call' : '/call',
          arguments: pending,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userRef = ConnectXDatabase.instance.ref('PublicUsers').child(uid);
    if (state == AppLifecycleState.resumed) {
      userRef.update({'online': true});
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      userRef.update({
        'online': false,
        'lastSeen': ServerValue.timestamp,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showProfile ? 'Profile' : 'ConnectX',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        leading: _showProfile
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _showProfile = false),
              )
            : null,
        actions: [
          if (_showProfile) ...[
            IconButton(
              tooltip: 'Edit profile',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEditProfile,
            ),
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _logout,
            ),
          ] else ...[
            if (_selectedTab == 0)
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => Navigator.of(context).pushNamed('/main/new'),
              ),
            if (_selectedTab == 1)
              IconButton(
                tooltip: 'Create status',
                icon: const Icon(Icons.camera_alt_outlined),
                onPressed: () => _UpdatesTab()._create(context),
              ),
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'profile') {
                  setState(() => _showProfile = true);
                } else if (value == 'new_group') {
                  _createGroup();
                } else if (value == 'settings') {
                  _openNotificationSettings();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new_group', child: Text('New group')),
                PopupMenuItem(value: 'profile', child: Text('Profile')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
        ],
        bottom: _showProfile
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: const [
                  Tab(text: 'CHATS'),
                  Tab(text: 'UPDATES'),
                  Tab(text: 'COMMUNITIES'),
                  Tab(text: 'CALLS'),
                ],
              ),
      ),
      body: _showProfile
          ? const ProfileScreen()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChatsTab(),
                const _UpdatesTab(),
                const _CommunitiesTab(),
                const _CallsTab(),
              ],
            ),
      floatingActionButton: _showProfile
          ? null
          : _selectedTab == 0
              ? FloatingActionButton(
                  onPressed: () => Navigator.of(context).pushNamed('/main/new'),
                  shape: const CircleBorder(),
                  child: const Icon(Icons.chat_rounded),
                )
              : _selectedTab == 1
                  ? FloatingActionButton(
                      onPressed: () => _UpdatesTab()._create(context),
                      shape: const CircleBorder(),
                      child: const Icon(Icons.camera_alt_rounded),
                    )
                  : _selectedTab == 2
                      ? FloatingActionButton.extended(
                          onPressed: () => _CommunitiesTab()._create(context),
                          icon: const Icon(Icons.groups_rounded),
                          label: const Text('New community'),
                        )
                      : FloatingActionButton(
                          onPressed: () => Navigator.of(context).pushNamed('/main/new'),
                          shape: const CircleBorder(),
                          child: const Icon(Icons.call_rounded),
                        ),
    );
  }

  Widget _buildChatsTab() {
    const filters = ['All', 'Unread', 'Favorites', 'Groups', 'Archived'];
    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            scrollDirection: Axis.horizontal,
            itemCount: filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = filters[index];
              final selected = _chatFilter == filter;
              return ChoiceChip(
                label: Text(filter),
                selected: selected,
                onSelected: (_) => setState(() => _chatFilter = filter),
              );
            },
          ),
        ),
        Expanded(
          child: _chatFilter == 'Groups'
              ? _GroupsList(onCreateGroup: _createGroup)
              : users.isEmpty && _chatFilter == 'All'
                  ? const _SectionEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'No chats yet',
                      description: 'Start a conversation with someone on ConnectX.',
                    )
                  : UserList(
                      users: users,
                      key: userListKey,
                      wantChats: true,
                      filter: _chatFilter,
                    )

        ),
      ],
    );
  }


  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final selected = <String>{};
    final available = users.where((person) =>
      person.key != FirebaseAuth.instance.currentUser!.uid).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create group'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: Column(children: [
              TextField(
                controller: nameController,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 8),
              const Align(alignment: Alignment.centerLeft,
                child: Text('Add members', style: TextStyle(fontWeight: FontWeight.w600))),
              Expanded(
                child: available.isEmpty
                  ? const Center(child: Text('No other contacts yet. You can create the group now and add members later.'))
                  : ListView(children: available.map((person) => CheckboxListTile(
                      value: selected.contains(person.key),
                      title: Text(person.name),
                      subtitle: Text('@${person.username}'),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) { selected.add(person.key); }
                        else { selected.remove(person.key); }
                      }),
                    )).toList()),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create')),
          ],
        ),
      ),
    );
    final groupName = nameController.text.trim();
    nameController.dispose();
    if (confirmed != true || groupName.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final members = <String>{uid, ...selected}.toList();
    try {
      final doc = FirebaseFirestore.instance.collection('groupChats').doc();
      await doc.set({
        'name': groupName,
        'createdBy': uid,
        'adminUids': [uid],
        'memberUids': members,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _chatFilter = 'Groups');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created.')),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create group: $error')),
      );
    }
  }

  Future<void> _openNotificationSettings() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = ConnectXDatabase.instance.ref('PrivateUsers').child(uid).child('notificationSettings');
    final snap = await ref.get();
    final saved = Map<String, dynamic>.from(snap.value is Map ? snap.value as Map : {});
    bool messages = saved['messages'] != false;
    bool groups = saved['groups'] != false;
    bool calls = saved['calls'] != false;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Notification settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(title: const Text('Direct messages'), value: messages,
            onChanged: (v) => setDialogState(() => messages = v)),
          SwitchListTile(title: const Text('Group messages'), value: groups,
            onChanged: (v) => setDialogState(() => groups = v)),
          SwitchListTile(title: const Text('Voice and video calls'), value: calls,
            onChanged: (v) => setDialogState(() => calls = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      )));
    if (confirmed == true) {
      await ref.set({'messages': messages, 'groups': groups, 'calls': calls});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification preferences saved.')));
    }
  }

  Future<void> _openEditProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = ConnectXDatabase.instance.ref("PublicUsers").child(uid);
    final snapshot = await ref.get();
    if (!mounted) return;

    final nameController = TextEditingController(
      text: snapshot.child('name').value?.toString() ??
          FirebaseAuth.instance.currentUser?.displayName ?? '',
    );
    final bioController = TextEditingController(
      text: snapshot.child('bio').value?.toString() ??
          snapshot.child('about').value?.toString() ?? '',
    );
    final currentPhotoUrl = snapshot.child('photoUrl').value?.toString() ??
        FirebaseAuth.instance.currentUser?.photoURL ?? '';
    XFile? pickedPhoto;
    var removePhoto = false;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundImage: pickedPhoto != null
                      ? FileImage(File(pickedPhoto!.path)) as ImageProvider<Object>
                      : (!removePhoto && currentPhotoUrl.isNotEmpty
                          ? NetworkImage(currentPhotoUrl) as ImageProvider<Object>
                          : null),
                  child: pickedPhoto == null && (removePhoto || currentPhotoUrl.isEmpty)
                      ? const Icon(Icons.person, size: 42)
                      : null,
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Change photo'),
                      onPressed: () async {
                        final image = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                          maxWidth: 1200,
                        );
                        if (image != null) {
                          setDialogState(() {
                            pickedPhoto = image;
                            removePhoto = false;
                          });
                        }
                      },
                    ),
                    if (currentPhotoUrl.isNotEmpty || pickedPhoto != null)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove photo'),
                        onPressed: () => setDialogState(() {
                          pickedPhoto = null;
                          removePhoto = true;
                        }),
                      ),
                  ],
                ),
                TextField(
                  controller: nameController,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                TextField(
                  controller: bioController,
                  maxLength: 160,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave == true && nameController.text.trim().isNotEmpty) {
      try {
        var photoUrl = currentPhotoUrl;
        var oldPhotoToDelete = '';
        if (pickedPhoto != null) {
          photoUrl = await ProfileStorage.upload(pickedPhoto!);
          oldPhotoToDelete = currentPhotoUrl;
        } else if (removePhoto) {
          photoUrl = '';
          oldPhotoToDelete = currentPhotoUrl;
        }

        final name = nameController.text.trim();
        await ref.update({
          'name': name,
          'bio': bioController.text.trim(),
          'photoUrl': photoUrl,
          'about': null,
        });
        await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(
          photoUrl.isEmpty ? null : photoUrl,
        );
        if (oldPhotoToDelete.isNotEmpty && oldPhotoToDelete != photoUrl) {
          try {
            await ProfileStorage.delete(oldPhotoToDelete);
          } catch (error) {
            // The new profile remains saved; an orphaned old image can be cleaned later.
            debugPrint('ConnectX old profile photo cleanup failed: $error');
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Profile update failed: $error')),
          );
        }
      }
    }

    nameController.dispose();
    bioController.dispose();
  }

  Future<void> _logout() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await ConnectXDatabase.instance.ref("PublicUsers").child(uid).child("online").set(false);
    }
    await NotificationService.dispose();
    await FirebaseAuth.instance.signOut();
    currentRoute = "/login";
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void getData() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    subscriptions.add(ConnectXDatabase.instance.ref("PrivateUsers").child(uid).child("chats")
        .child("personal").orderByValue().limitToLast(30).onValue.listen((event) {
      for (final snapshot in event.snapshot.children) {
        final chatId = snapshot.key;
        final timestamp = snapshot.value;
        if (chatId == null || timestamp is! int) continue;
        final existingIndex = chats.indexWhere((chat) => chat.id == chatId);
        if (existingIndex == -1) {
          final newChat = Chat(timestamp, chatId);
          chats.add(newChat);
          subscriptions.add(ConnectXDatabase.instance.ref("PublicUsers").child(chatId)
              .onValue.listen((userEvent) {
            final newUser = User1.getFromSnapshot(userEvent.snapshot);
            final index = users.indexWhere((user) => user.key == newUser.key);
            if (!mounted) return;
            setState(() {
              if (index == -1) {
                users.add(newUser);
              } else {
                users[index] = newUser;
              }
              users.sort((a, b) {
                final aIndex = chats.indexWhere((chat) => chat.id == a.key);
                final bIndex = chats.indexWhere((chat) => chat.id == b.key);
                return bIndex.compareTo(aIndex);
              });
            });
          }));
        } else if (chats[existingIndex].timestamp != timestamp) {
          chats[existingIndex] = Chat(timestamp, chatId);
        }
      }
      chats.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}


class _GroupsList extends StatelessWidget {
  final VoidCallback onCreateGroup;
  const _GroupsList({required this.onCreateGroup});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Column(children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onCreateGroup,
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('New group'),
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('groupChats')
              .where('memberUids', arrayContains: uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Unable to load groups: ${snapshot.error}'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final groups = snapshot.data!.docs;
            if (groups.isEmpty) return const _SectionEmptyState(
              icon: Icons.groups_outlined,
              title: 'No group chats yet',
              description: 'Create a group to start a group conversation.',
            );
            return ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index].data();
                final name = (group['name'] ?? 'Group').toString();
                final count = (group['memberUids'] as List?)?.length ?? 0;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$count members'),
                  onTap: () => Navigator.of(context).pushNamed('/group',
                    arguments: {'groupId': groups[index].id, 'name': name}),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _UpdatesTab extends StatelessWidget {
  const _UpdatesTab();

  Future<void> _create(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final kind = await showModalBottomSheet<String>(context: context,
      builder: (c) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.text_fields), title: const Text('Text status'), onTap: () => Navigator.pop(c, 'text')),
        ListTile(leading: const Icon(Icons.photo), title: const Text('Photo status'), onTap: () => Navigator.pop(c, 'image')),
        ListTile(leading: const Icon(Icons.videocam), title: const Text('Video status'), onTap: () => Navigator.pop(c, 'video')),
      ])));
    if (kind == null) return;
    final audience = await showDialog<List<String>>(context: context, builder: (dialogContext) {
      final selected = <String>{uid, ...users.where((u) => u.key != uid).map((u) => u.key)};
      return StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Status privacy'),
        content: SizedBox(width: double.maxFinite, height: 340, child: Column(children: [
          const Text('Select the contacts who can view this status.'),
          Expanded(child: ListView(children: users.where((u) => u.key != uid).map((person) =>
            CheckboxListTile(dense: true, value: selected.contains(person.key),
              title: Text(person.name), subtitle: Text('@${person.username}'),
              onChanged: (value) => setDialogState(() {
                if (value == true) selected.add(person.key); else selected.remove(person.key);
              }),
            )).toList())),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, selected.toList()), child: const Text('Done')),
        ],
      ));
    });
    if (audience == null) return;
    String text = '';
    String? url, fileName;
    if (kind == 'text') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Create text status'),
        content: TextField(controller: controller, maxLength: 500, maxLines: 4,
          decoration: const InputDecoration(hintText: 'What would you like to share?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Share')),
        ]));
      text = controller.text.trim();
      controller.dispose();
      if (ok != true || text.isEmpty) return;
    } else {
      final picker = ImagePicker();
      final picked = kind == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30))
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 82);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 25 * 1024 * 1024) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum status media size is 25 MB.')));
        return;
      }
      fileName = picked.name;
      final ext = picked.name.split('.').last.toLowerCase();
      final mime = kind == 'video' ? (ext == 'mov' ? 'video/quicktime' : 'video/mp4')
        : (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
      try {
        url = await ChatStorage.upload(
          conversationId: '$uid,$uid',
          fileName: picked.name,
          bytes: bytes,
          contentType: mime,
          resourceType: 'status',
          audienceUids: audience,
        );
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $error')));
        return;
      }
    }
    try {
      await FirebaseFirestore.instance.collection('statuses').add({
        'ownerUid': uid,
        'userName': FirebaseAuth.instance.currentUser?.displayName ?? 'ConnectX user',
        'statusText': text,
        'mediaType': kind,
        if (url != null) 'mediaUrl': url,
        if (fileName != null) 'fileName': fileName,
        'audienceUids': audience.toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status shared for 24 hours.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share status: $error')));
    }
  }

  Future<void> _view(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc, String uid) async {
    final data = doc.data();
    if (data['ownerUid'] != uid) {
      try { await doc.reference.collection('views').doc(uid).set({'viewerUid': uid, 'viewedAt': FieldValue.serverTimestamp()}); } catch (_) {}
    }
    if (!context.mounted) return;
    final type = (data['mediaType'] ?? 'text').toString();
    var statusMediaUrl = data['mediaUrl']?.toString();
    if (statusMediaUrl != null && (type == 'image' || type == 'video')) {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final uri = Uri.tryParse(statusMediaUrl);
      if (token != null && uri != null) {
        statusMediaUrl = uri.replace(queryParameters: {
          ...uri.queryParameters,
          'auth': token,
        }).toString();
      }
    }
    await showDialog<void>(context: context, builder: (c) => Dialog(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: Text((data['userName'] ?? 'ConnectX user').toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close))]),
        if (type == 'image' && statusMediaUrl != null)
          Image.network(statusMediaUrl, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Unable to load photo'))
        else if (type == 'video' && statusMediaUrl != null)
          ListTile(leading: const Icon(Icons.play_circle), title: Text((data['fileName'] ?? 'Video status').toString()),
            onTap: () { final uri = Uri.tryParse(statusMediaUrl!); if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication); })
        else
          Padding(padding: const EdgeInsets.all(24), child: SelectableText((data['statusText'] ?? '').toString(), style: const TextStyle(fontSize: 20))),
        if (data['ownerUid'] == uid)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: doc.reference.collection('views').snapshots(),
            builder: (_, snap) => Align(alignment: Alignment.centerLeft, child: Text('Seen by ${snap.data?.docs.length ?? 0}'))),
      ]))));
  }

  Future<void> _showViewers(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final views = await doc.reference.collection('views').get();
    final rows = await Future.wait(views.docs.map((view) async {
      final uid = view.id;
      final name = await ConnectXDatabase.instance.ref('PublicUsers').child(uid).child('name').get();
      return name.value?.toString() ?? 'ConnectX user';
    }));
    if (!context.mounted) return;
    await showDialog<void>(context: context, builder: (c) => AlertDialog(
      title: Text('Seen by ${rows.length}'),
      content: SizedBox(width: double.maxFinite, child: rows.isEmpty
        ? const Text('No views yet.')
        : ListView(shrinkWrap: true, children: rows.map((name) =>
            ListTile(leading: const Icon(Icons.person_outline), title: Text(name))).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('statuses')
        .where('audienceUids', arrayContains: uid)
        .where('expiresAt', isGreaterThan: Timestamp.now()).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to load updates: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final now = Timestamp.now();
        final docs = snapshot.data!.docs.where((d) => d.data()['expiresAt'] is Timestamp &&
          (d.data()['expiresAt'] as Timestamp).compareTo(now) > 0).toList()
          ..sort((a,b) => ((b.data()['createdAt'] is Timestamp) ? b.data()['createdAt'] as Timestamp : Timestamp(0,0))
            .compareTo((a.data()['createdAt'] is Timestamp) ? a.data()['createdAt'] as Timestamp : Timestamp(0,0)));
        final mine = docs.where((d) => d.data()['ownerUid'] == uid).toList();
        final others = docs.where((d) => d.data()['ownerUid'] != uid).toList();
        Widget statusTile(QueryDocumentSnapshot<Map<String, dynamic>> d, bool own) {
          final data = d.data(), type = (d.data()['mediaType'] ?? 'text').toString();
          return ListTile(
            leading: CircleAvatar(child: Icon(type == 'video' ? Icons.videocam : type == 'image' ? Icons.image : Icons.text_fields)),
            title: Text(own ? (data['statusText'] ?? data['fileName'] ?? 'My status').toString() : (data['userName'] ?? 'Contact').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: own
              ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: d.reference.collection('views').snapshots(),
                  builder: (_, v) => Text('Seen by ${v.data?.docs.length ?? 0} · 24-hour status'))
              : Text((data['statusText'] ?? data['fileName'] ?? 'Media status').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _view(context, d, uid),
            trailing: own ? PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'views') _showViewers(context, d);
                if (value == 'delete') d.reference.delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'views', child: Text('View seen list')),
                PopupMenuItem(value: 'delete', child: Text('Delete status')),
              ],
            ) : null,
          );
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16,12,16,90), children: [
          Text('Status', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.add_a_photo)),
            title: const Text('My status'), subtitle: const Text('Add text, photo or video'),
            onTap: () => _create(context), trailing: IconButton(icon: const Icon(Icons.add), onPressed: () => _create(context))),
          ...mine.map((d) => statusTile(d, true)),
          const Divider(height: 24),
          Text('Recent updates', style: Theme.of(context).textTheme.titleSmall),
          if (others.isEmpty) const _SectionEmptyState(icon: Icons.circle_outlined, title: 'No recent updates', description: 'Statuses from your contacts appear here.')
          else ...others.map((d) => statusTile(d, false)),
          const Divider(height: 28),
          const _ChannelsPanel(),
        ]);
      });
  }
}

class _CommunitiesTab extends StatelessWidget {
  const _CommunitiesTab();

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Create community'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, maxLength: 50, decoration: const InputDecoration(labelText: 'Community name')),
        TextField(controller: description, maxLength: 240, maxLines: 3,
          decoration: const InputDecoration(labelText: 'Description')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create')),
      ],
    ));
    final title = name.text.trim(), about = description.text.trim();
    name.dispose(); description.dispose();
    if (ok != true || title.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await FirebaseFirestore.instance.collection('communities').add({
        'name': title, 'description': about, 'ownerUid': uid,
        'adminUids': [uid], 'memberUids': [uid],
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Community created.')),
      );
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create community: $error')),
      );
    }
  }

  Future<void> _open(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = doc.reference;
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * .82,
        child: Column(children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? initial;
              final currentMembers = List<String>.from(data['memberUids'] ?? []);
              final isMember = currentMembers.contains(uid);
              final admins = List<String>.from(data['adminUids'] ?? [data['ownerUid']].whereType<String>());
              final isAdmin = admins.contains(uid) || data['ownerUid'] == uid;
              return Column(children: [
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
                  title: Text((data['name'] ?? 'Community').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${data['description'] ?? ''}\n${currentMembers.length} members'),
                  isThreeLine: true,
                ),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: data['ownerUid'] == uid ? null : () async {
                      try {
                        await ref.update({'memberUids': isMember
                          ? FieldValue.arrayRemove([uid])
                          : FieldValue.arrayUnion([uid])});
                      } catch (error) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Membership update failed: $error')),
                        );
                      }
                    },
                    icon: Icon(data['ownerUid'] == uid ? Icons.verified_user
                      : isMember ? Icons.exit_to_app : Icons.group_add),
                    label: Text(data['ownerUid'] == uid ? 'Owner'
                      : isMember ? 'Leave community' : 'Join community'),
                  )),
                  if (isAdmin) const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Chip(avatar: Icon(Icons.shield_outlined, size: 16), label: Text('Admin')),
                  ),
                ])),
              ]);
            },
          ),
          const Divider(),
          Expanded(child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, membership) {
              final community = membership.data?.data() ?? initial;
              final canRead = List<String>.from(community['memberUids'] ?? []).contains(uid);
              if (!canRead) return const Center(child: Text('Join this community to view its discussions.'));
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ref.collection('posts').orderBy('createdAt', descending: true).limit(100).snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text('Unable to load community posts: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  if (snap.data!.docs.isEmpty) return const Center(child: Text('No posts yet. Start the discussion.'));
                  return ListView(children: snap.data!.docs.map((post) {
                    final postData = post.data();
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.forum_outlined)),
                      title: Text((postData['text'] ?? '').toString()),
                      subtitle: Text('${postData['authorName'] ?? 'Community member'} · ${postData['createdAt'] is Timestamp ? DateFormat('dd MMM, h:mm a').format((postData['createdAt'] as Timestamp).toDate()) : 'Just now'}'),
                    );
                  }).toList());
                },
              );
            },
          )),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? initial;
              final isMember = List<String>.from(data['memberUids'] ?? []).contains(uid);
              final admins = List<String>.from(data['adminUids'] ?? [data['ownerUid']].whereType<String>());
              final isAdmin = admins.contains(uid) || data['ownerUid'] == uid;
              if (!isMember) return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Join this community to participate in discussions.'),
              );
              return Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
                child: Row(children: [
                  Expanded(child: TextField(controller: controller, minLines: 1, maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Write a community post'))),
                  IconButton(
                    tooltip: 'Publish post',
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      try {
                        await ref.collection('posts').add({
                          'text': text, 'authorUid': uid,
                          'authorName': FirebaseAuth.instance.currentUser?.displayName ?? 'ConnectX member',
                          'createdAt': FieldValue.serverTimestamp(),
                          'isAdminPost': isAdmin,
                        });
                        controller.clear();
                      } catch (error) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Post failed: $error')),
                        );
                      }
                    },
                    icon: const Icon(Icons.send_rounded),
                  ),
                ]),
              );
            },
          ),
        ]),
      )),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('communities').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Unable to load communities: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('Communities', style: Theme.of(context).textTheme.headlineSmall),
          const Text('Create or join communities and take part in group discussions.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => _create(context),
            icon: const Icon(Icons.add), label: const Text('Create community')),
          if (docs.isEmpty) const Padding(
            padding: EdgeInsets.all(28),
            child: _SectionEmptyState(icon: Icons.groups_outlined,
              title: 'No communities yet', description: 'Create a community and invite people to join.'),
          ),
          ...docs.map((doc) {
            final data = doc.data();
            final members = List<String>.from(data['memberUids'] ?? []);
            final joined = members.contains(uid);
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups)),
                title: Text((data['name'] ?? 'Community').toString()),
                subtitle: Text('${data['description'] ?? ''} · ${members.length} members',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Icon(joined ? Icons.check_circle : Icons.chevron_right,
                  color: joined ? Colors.green : null),
                onTap: () => _open(context, doc),
              ),
            );
          }),
        ]);
      },
    );
  }
}

class _ChannelsPanel extends StatelessWidget {
  const _ChannelsPanel();

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController(), description = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Create channel'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Channel name')),
        TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create'))],
    ));
    final title = name.text.trim(), about = description.text.trim();
    name.dispose(); description.dispose();
    if (ok != true || title.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('channels').add({
      'name': title, 'description': about, 'ownerUid': uid, 'memberUids': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _open(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final data = doc.data();
    if (!context.mounted) return;
    final controller = TextEditingController();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      builder: (c) => SafeArea(child: SizedBox(height: MediaQuery.of(c).size.height * .75,
        child: Column(children: [
          ListTile(
            title: Text((data['name'] ?? 'Channel').toString()),
            subtitle: Text((data['description'] ?? '').toString()),
            trailing: data['ownerUid'] == uid ? const Chip(label: Text('Owner')) :
              OutlinedButton(
                onPressed: () async {
                  final members = List<String>.from(data['memberUids'] ?? []);
                  final follows = members.contains(uid);
                  try {
                    await doc.reference.update({'memberUids': follows
                      ? FieldValue.arrayRemove([uid])
                      : FieldValue.arrayUnion([uid])});
                    if (c.mounted) Navigator.pop(c);
                  } catch (error) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not update channel membership: $error')),
                    );
                  }
                },
                child: Text(List<String>.from(data['memberUids'] ?? []).contains(uid) ? 'Unfollow' : 'Follow'),
              ),
          ),
          Expanded(child: List<String>.from(data['memberUids'] ?? []).contains(uid) || data['ownerUid'] == uid
            ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: doc.reference.collection('posts').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Unable to load posts: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return ListView(children: snap.data!.docs.map((post) => ListTile(
                title: Text((post.data()['text'] ?? '').toString()),
                subtitle: Text((post.data()['authorName'] ?? 'Channel admin').toString()),
              )).toList());
            })
            : const Center(child: Text('Follow this channel to view its posts.'))),
          if (data['ownerUid'] == uid)
            Padding(padding: const EdgeInsets.all(8), child: Row(children: [
              Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Announcement'))),
              IconButton(icon: const Icon(Icons.send), onPressed: () async {
                final text = controller.text.trim(); if (text.isEmpty) return;
                await doc.reference.collection('posts').add({'text': text, 'authorUid': uid,
                  'authorName': FirebaseAuth.instance.currentUser?.displayName ?? 'Admin',
                  'createdAt': FieldValue.serverTimestamp()});
                controller.clear();
              }),
            ])),
        ]))));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Channels', style: Theme.of(context).textTheme.titleLarge),
        TextButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.add), label: const Text('Create')),
      ]),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('channels').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Text('Unable to load channels: ${snap.error}');
          if (!snap.hasData) return const LinearProgressIndicator();
          if (snap.data!.docs.isEmpty) return const Text('No channels available yet.');
          return Column(children: snap.data!.docs.map((doc) => ListTile(
            leading: const CircleAvatar(child: Icon(Icons.campaign_outlined)),
            title: Text((doc.data()['name'] ?? 'Channel').toString()),
            subtitle: Text('${(doc.data()['memberUids'] as List? ?? []).length} followers'),
            onTap: () => _open(context, doc),
          )).toList());
        },
      ),
    ]);
  }
}

class _CallsTab extends StatelessWidget {
  const _CallsTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('calls')
        .where('participants', arrayContains: uid).snapshots(),
      builder: (context, directSnapshot) {
        if (directSnapshot.hasError) return Center(child: Text('Unable to load calls: ${directSnapshot.error}'));
        if (!directSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final directCalls = directSnapshot.data!.docs.toList()
          ..sort((a, b) {
            final aa = a.data()['createdAt'], bb = b.data()['createdAt'];
            return (bb is Timestamp ? bb : Timestamp(0, 0))
              .compareTo(aa is Timestamp ? aa : Timestamp(0, 0));
          });
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('groupCalls')
            .where('participants', arrayContains: uid).snapshots(),
          builder: (context, groupSnapshot) {
            if (groupSnapshot.hasError) return Center(child: Text('Unable to load group calls: ${groupSnapshot.error}'));
            if (!groupSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            final groupCalls = groupSnapshot.data!.docs.toList()
              ..sort((a, b) {
                final aa = a.data()['createdAt'], bb = b.data()['createdAt'];
                return (bb is Timestamp ? bb : Timestamp(0, 0))
                  .compareTo(aa is Timestamp ? aa : Timestamp(0, 0));
              });
            if (directCalls.isEmpty && groupCalls.isEmpty) {
              return const _SectionEmptyState(icon: Icons.call_outlined,
                title: 'No calls yet', description: 'Your voice, video and group call history will appear here.');
            }
            return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
              if (directCalls.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.all(16), child: Text('Recent calls',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                ...directCalls.map((doc) {
                  final data = doc.data();
                  final incoming = data['calleeUid'] == uid;
                  final ringing = data['status'] == 'ringing' && incoming;
                  final video = data['type'] == 'video';
                  final peerName = (incoming ? data['callerName'] : data['calleeName']) ?? 'ConnectX user';
                  final status = (data['status'] ?? 'unknown').toString();
                  return ListTile(
                    leading: CircleAvatar(child: Icon(video ? Icons.videocam : Icons.call)),
                    title: Text(peerName.toString()),
                    subtitle: Text(ringing ? 'Incoming ${video ? 'video' : 'voice'} call' :
                      '${incoming ? 'Incoming' : 'Outgoing'} · $status'),
                    trailing: ringing ? IconButton(icon: const Icon(Icons.call, color: Colors.green),
                      onPressed: () => Navigator.of(context).pushNamed('/call', arguments: {
                        'callId': doc.id, 'peerUid': data['callerUid'].toString(),
                        'peerName': peerName.toString(), 'isCaller': false, 'isVideo': video,
                      })) : null,
                  );
                }),
              ],
              if (groupCalls.isNotEmpty) ...[
                const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text('Group calls',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                ...groupCalls.map((doc) {
                  final data = doc.data();
                  final expiry = data['expiresAt'];
                  final active = data['status'] == 'active'
                    && expiry is Timestamp && expiry.toDate().isAfter(DateTime.now());
                  final type = data['type'] == 'video' ? 'Video' : 'Voice';
                  final activeUids = List<String>.from(data['activeUids'] ?? []);
                  return ListTile(
                    leading: CircleAvatar(child: Icon(type == 'Video' ? Icons.video_call : Icons.groups)),
                    title: Text((data['groupName'] ?? 'Group call').toString()),
                    subtitle: Text('$type group call · ${active ? 'Active (${activeUids.length} joined)' : (data['status'] ?? 'Ended')}'),
                    trailing: active ? IconButton(
                      tooltip: 'Join group call',
                      icon: const Icon(Icons.call, color: Colors.green),
                      onPressed: () => Navigator.of(context).pushNamed('/group-call', arguments: {
                        'callId': doc.id,
                        'groupId': data['groupId'].toString(),
                        'groupName': (data['groupName'] ?? 'Group').toString(),
                        'callType': data['type'] ?? 'voice',
                        'isCreator': false,
                        'isGroupCall': true,
                      }),
                    ) : null,
                  );
                }),
              ],
            ]);
          },
        );
      },
    );
  }
}

class _SectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _SectionEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.65)),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                )),
          ],
        ),
      ),
    );
  }
}
