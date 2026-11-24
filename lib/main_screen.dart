import 'dart:async';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/chat_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectx/models/chat.dart';
import 'package:connectx/utils/user_list.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'main.dart';
import 'models/user.dart';
import 'profile_screen.dart';

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
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseDatabase.instance.ref("Users").child(uid);
    userRef.onDisconnect().update({
      'online': false,
      'lastSeen': ServerValue.timestamp,
    });
    userRef.update({'online': true});
    getData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userRef = FirebaseDatabase.instance.ref('Users').child(uid);
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
                onPressed: () => _showComingSoon('Create status'),
              ),
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'profile') {
                  setState(() => _showProfile = true);
                } else if (value == 'new_group') {
                  _createGroup();
                } else if (value == 'settings') {
                  _showComingSoon('Settings');
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
                      onPressed: () => _showComingSoon('Create status'),
                      shape: const CircleBorder(),
                      child: const Icon(Icons.camera_alt_rounded),
                    )
                  : _selectedTab == 2
                      ? FloatingActionButton.extended(
                          onPressed: () => _showComingSoon('Create community'),
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

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature will be added in the next feature stage.')),
    );
  }

  Future<void> _openEditProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseDatabase.instance.ref("Users").child(uid);
    final snapshot = await ref.get();
    if (!mounted) return;
    final nameController = TextEditingController(
      text: snapshot.child('name').value?.toString() ??
          FirebaseAuth.instance.currentUser?.displayName ?? '',
    );
    final aboutController = TextEditingController(
      text: snapshot.child('about').value?.toString() ?? 'Available on ConnectX',
    );
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            TextField(
              controller: aboutController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'About',
                prefixIcon: Icon(Icons.info_outline),
              ),
            ),
          ],
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
    );
    if (shouldSave == true && nameController.text.trim().isNotEmpty) {
      final name = nameController.text.trim();
      await ref.update({'name': name, 'about': aboutController.text.trim()});
      await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    }
    nameController.dispose();
    aboutController.dispose();
  }

  Future<void> _logout() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseDatabase.instance.ref("Users").child(uid).child("online").set(false);
    }
    await FirebaseAuth.instance.signOut();
    currentRoute = "/login";
    if (!mounted) return;
    await Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void getData() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    FirebaseDatabase.instance.ref("Users").child(uid).child("chats")
        .child("personal").limitToFirst(15).onValue.listen((event) {
      for (final snapshot in event.snapshot.children) {
        final chatId = snapshot.key;
        final timestamp = snapshot.value;
        if (chatId == null || timestamp is! int) continue;
        final existingIndex = chats.indexWhere((chat) => chat.id == chatId);
        if (existingIndex == -1) {
          final newChat = Chat(timestamp, chatId);
          chats.add(newChat);
          subscriptions.add(FirebaseDatabase.instance.ref("Users").child(chatId)
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
    });
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
    final audience = <String>{uid, ...users.where((u) => u.key != uid).map((u) => u.key)};
    final privacy = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Status privacy'),
      content: const Text('Share this status with your ConnectX chat contacts?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Contacts')),
      ]));
    if (privacy != true) return;
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
        url = await ChatStorage.upload(conversationId: '$uid,$uid',
          fileName: picked.name, bytes: bytes, contentType: mime);
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
    await showDialog<void>(context: context, builder: (c) => Dialog(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: Text((data['userName'] ?? 'ConnectX user').toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close))]),
        if (type == 'image' && data['mediaUrl'] != null)
          Image.network(data['mediaUrl'].toString(), fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('Unable to load photo'))
        else if (type == 'video' && data['mediaUrl'] != null)
          ListTile(leading: const Icon(Icons.play_circle), title: Text((data['fileName'] ?? 'Video status').toString()),
            onTap: () { final uri = Uri.tryParse(data['mediaUrl'].toString()); if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication); })
        else
          Padding(padding: const EdgeInsets.all(24), child: SelectableText((data['statusText'] ?? '').toString(), style: const TextStyle(fontSize: 20))),
        if (data['ownerUid'] == uid)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: doc.reference.collection('views').snapshots(),
            builder: (_, snap) => Align(alignment: Alignment.centerLeft, child: Text('Seen by ${snap.data?.docs.length ?? 0}'))),
      ]))));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('statuses').where('audienceUids', arrayContains: uid).snapshots(),
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
            trailing: own ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => d.reference.delete()) : null,
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
        ]);
      });
  }
}

class _CommunitiesTab extends StatelessWidget {
  const _CommunitiesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      children: [
        Container(
          height: 170,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(Icons.groups_rounded,
              size: 76, color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        const SizedBox(height: 24),
        Text('Bring groups together',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
          'Organize related groups in one place. Share announcements and keep community conversations connected.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Community creation will be enabled in the next feature stage.')),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Start a community'),
        ),
      ],
    );
  }
}

class _CallsTab extends StatelessWidget {
  const _CallsTab();

  @override
  Widget build(BuildContext context) {
    return const _SectionEmptyState(
      icon: Icons.call_outlined,
      title: 'No calls yet',
      description: 'Your voice and video call history will appear here. Start a call from a chat.',
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
