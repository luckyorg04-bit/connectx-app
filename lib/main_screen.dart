import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'services/chat_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectx/models/chat.dart';
import 'package:connectx/utils/user_list.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'utils/app_feedback.dart';
import 'main.dart';
import 'app_navigator.dart';
import 'models/user.dart';
import 'profile_screen.dart';
import 'services/notification_service.dart';
import 'services/database_service.dart';
import 'services/app_preferences.dart';

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
  String _chatSearch = '';
  final TextEditingController _chatSearchController = TextEditingController();

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
        title: _showProfile
            ? const Text('Profile', style: TextStyle(fontWeight: FontWeight.w700))
            : const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.forum_rounded, size: 21, color: Colors.white),
                SizedBox(width: 9),
                Text('ConnectX', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.25)),
              ]),
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
              onPressed: () => Navigator.of(context).pushNamed('/edit-profile'),
            ),
            IconButton(
              tooltip: _isLoggingOut ? 'Logging out' : 'Log out',
              icon: _isLoggingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.logout_rounded),
              onPressed: _isLoggingOut ? null : _logout,
            ),
          ] else ...[
            if (_selectedTab == 0) ...[
              IconButton(
                tooltip: 'Create status',
                icon: const Icon(Icons.camera_alt_outlined),
                onPressed: () => _UpdatesTab()._create(context),
              ),
              IconButton(
                tooltip: 'Search contacts',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => Navigator.of(context).pushNamed('/main/new'),
              ),
            ],
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
                  Navigator.of(context).pushNamed('/settings');
                } else if (value == 'my_qr') {
                  Navigator.of(context).pushNamed('/my-qr');
                } else if (value == 'scan_qr') {
                  Navigator.of(context).pushNamed('/scan-qr');
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new_group', child: Text('New group')),
                PopupMenuItem(value: 'profile', child: Text('Profile')),
                PopupMenuItem(value: 'my_qr', child: Text('My QR code')),
                PopupMenuItem(value: 'scan_qr', child: Text('Scan QR code')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
        ],
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
      bottomNavigationBar: _showProfile
          ? null
          : NavigationBar(
              selectedIndex: _selectedTab,
              onDestinationSelected: (index) {
                _tabController.animateTo(index);
                setState(() => _selectedTab = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline_rounded),
                  selectedIcon: Icon(Icons.chat_rounded),
                  label: 'Chats',
                ),
                NavigationDestination(
                  icon: Icon(Icons.circle_outlined),
                  selectedIcon: Icon(Icons.donut_large_rounded),
                  label: 'Updates',
                ),
                NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups_rounded),
                  label: 'Communities',
                ),
                NavigationDestination(
                  icon: Icon(Icons.call_outlined),
                  selectedIcon: Icon(Icons.call_rounded),
                  label: 'Calls',
                ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: SizedBox(
            height: 46,
            child: TextField(
              controller: _chatSearchController,
              onChanged: (value) => setState(() => _chatSearch = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search chats or people',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _chatSearch.isEmpty ? null : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _chatSearchController.clear();
                    _chatSearch = '';
                  }),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF202C33) : const Color(0xFFF0F2F5),
              ),
            ),
          ),
        ),
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
                selectedColor: const Color(0xFFD9FDD3),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF202C33) : const Color(0xFFF0F2F5),
                side: BorderSide.none,
                labelStyle: TextStyle(
                  color: selected ? const Color(0xFF075E54) : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                onSelected: (_) => setState(() => _chatFilter = filter),
              );
            },
          ),
        ),
        Expanded(
          child: _chatFilter == 'Groups'
              ? _GroupsList(onCreateGroup: _createGroup, searchQuery: _chatSearch)
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
                      searchQuery: _chatSearch,
                    )

        ),
      ],
    );
  }


  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
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
            height: (MediaQuery.of(context).size.height * .58).clamp(280.0, 420.0).toDouble(),
            child: Column(children: [
              TextField(
                controller: nameController,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              TextField(
                controller: descriptionController,
                maxLength: 512,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Group description (optional)'),
              ),
              const SizedBox(height: 8),
              const Align(alignment: Alignment.centerLeft,
                child: Text('Add members', style: TextStyle(fontWeight: FontWeight.w600))),
              Expanded(
                child: available.isEmpty
                  ? const Center(child: Text('Start a chat with at least one person before creating a group.'))
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
            FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('Create')),
          ],
        ),
      ),
    );
    final groupName = nameController.text.trim();
    final groupDescription = descriptionController.text.trim();
    nameController.dispose();
    descriptionController.dispose();
    if (confirmed != true || groupName.isEmpty || selected.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final members = <String>{uid, ...selected}.toList();
    try {
      final doc = FirebaseFirestore.instance.collection('groupChats').doc();
      await doc.set({
        'name': groupName,
        'description': groupDescription,
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
      showConnectXErrorDialog(context, 'Could not create group. Check your connection and try again.');
    }
  }

  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid;
    final isGoogleSession = currentUser?.providerData.any((provider) => provider.providerId == 'google.com') ?? false;
    // Presence and notification cleanup are best-effort. They must never
    // prevent Firebase Auth from signing the user out.
    try {
      if (uid != null) {
        await ConnectXDatabase.instance
            .ref('PublicUsers')
            .child(uid)
            .update({'online': false, 'lastSeen': ServerValue.timestamp})
            .timeout(const Duration(seconds: 4));
      }
    } catch (error) {
      debugPrint('ConnectX logout presence cleanup failed: $error');
    }
    // Stop account-scoped listeners before clearing the authenticated session.
    final activeSubscriptions = List<StreamSubscription>.from(subscriptions);
    subscriptions.clear();
    users.clear();
    chats.clear();
    try {
      await Future.wait(activeSubscriptions.map((subscription) => subscription.cancel()))
          .timeout(const Duration(seconds: 4));
    } catch (error) {
      debugPrint('ConnectX logout listener cleanup failed: $error');
    }
    try {
      await NotificationService.dispose().timeout(const Duration(seconds: 4));
    } catch (error) {
      debugPrint('ConnectX logout notification cleanup failed: $error');
    }
    if (isGoogleSession) {
      try {
        await GoogleSignIn().signOut().timeout(const Duration(seconds: 4));
      } catch (error) {
        debugPrint('ConnectX Google session cleanup failed: $error');
      }
    }
    try {
      await FirebaseAuth.instance.signOut().timeout(const Duration(seconds: 8));
    } catch (error) {
      debugPrint('ConnectX Firebase sign-out failed: $error');
      // The user is still authenticated; restore the home data listeners.
      if (mounted) {
        getData();
        setState(() => _isLoggingOut = false);
      }
      return;
    }
    AppPreferences.reset();
    pendingCallArguments = null;
    pendingDirectChatUid = null;
    currentRoute = '/login';
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
    _chatSearchController.dispose();
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}


class _GroupsList extends StatelessWidget {
  final VoidCallback onCreateGroup;
  final String searchQuery;
  const _GroupsList({required this.onCreateGroup, required this.searchQuery});

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
            if (snapshot.hasError) return const _SectionEmptyState(icon: Icons.cloud_off_outlined, title: 'Groups are unavailable', description: 'ConnectX could not load your groups. Check your connection and try again.') ;
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final query = searchQuery.trim().toLowerCase();
            final groups = snapshot.data!.docs.where((doc) {
              final name = (doc.data()['name'] ?? 'Group').toString().toLowerCase();
              return query.isEmpty || name.contains(query);
            }).toList();
            if (groups.isEmpty) return _SectionEmptyState(
              icon: Icons.groups_outlined,
              title: query.isEmpty ? 'No group chats yet' : 'No matching groups',
              description: query.isEmpty ? 'Create a group to start a group conversation.' : 'Try another group name.',
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
    // Status audience must include registered users, not only the recent-chat
    // list. The latter is intentionally limited to active conversations.
    final audienceSet = <String>{uid};
    try {
      final publicUsers = await ConnectXDatabase.instance
          .ref('PublicUsers').get().timeout(const Duration(seconds: 10));
      audienceSet.addAll(publicUsers.children
          .map((profile) => profile.key)
          .whereType<String>()
          .where((userUid) => userUid.isNotEmpty));
    } catch (error) {
      debugPrint('ConnectX status audience lookup failed: $error');
      audienceSet.addAll(users.map((user) => user.key).where((userUid) => userUid.isNotEmpty));
    }
    final orderedAudience = audienceSet.toList()..sort();
    orderedAudience.remove(uid);
    final audience = <String>[uid, ...orderedAudience].take(500).toList();
    if (audienceSet.length > 500) {
      debugPrint('ConnectX status audience capped at 500 users by media API limit.');
    }
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
        showConnectXErrorDialog(context, 'Media upload failed. Check your connection and try again.');
        return;
      }
    }
    var statusOwnerName = FirebaseAuth.instance.currentUser?.displayName ?? 'ConnectX user';
    var statusOwnerPhotoUrl = FirebaseAuth.instance.currentUser?.photoURL ?? '';
    try {
      final profileSnapshot = await ConnectXDatabase.instance
          .ref('PublicUsers').child(uid).get();
      final savedName = profileSnapshot.child('name').value?.toString() ?? '';
      final savedPhotoUrl = profileSnapshot.child('photoUrl').value?.toString() ?? '';
      if (savedName.trim().isNotEmpty) statusOwnerName = savedName.trim();
      if (savedPhotoUrl.isNotEmpty) statusOwnerPhotoUrl = savedPhotoUrl;
    } catch (error) {
      debugPrint('ConnectX status profile lookup failed: $error');
    }
    try {
      await FirebaseFirestore.instance.collection('statuses').add({
        'ownerUid': uid,
        'userName': statusOwnerName,
        'userPhotoUrl': statusOwnerPhotoUrl,
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
      showConnectXErrorDialog(context, 'Status could not be shared. Please try again.');
    }
  }

  Future<void> _viewGroup(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    String uid,
  ) async {
    if (items.isEmpty || !context.mounted) return;
    // Present a user's statuses oldest-to-newest, like a WhatsApp story sequence.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog.fullscreen(
        child: _StatusStoryViewer(
          statuses: items.reversed.toList(),
          viewerUid: uid,
        ),
      ),
    );
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
      // Keep the realtime audience query independent of the expiry range.
      // Expiry is filtered below so a missing composite index cannot hide
      // successfully published statuses from the entire feed.
      stream: FirebaseFirestore.instance.collection('statuses')
          .where('audienceUids', arrayContains: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('ConnectX status feed stream failed: ${snapshot.error}');
          return const _SectionEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Updates are unavailable',
            description: 'ConnectX could not load updates. Check your connection or try again later.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final now = Timestamp.now();
        final activeStatuses = snapshot.data!.docs.where((doc) {
          final expiry = doc.data()['expiresAt'];
          return expiry is Timestamp && expiry.compareTo(now) > 0;
        }).toList();

        DateTime statusDate(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final createdAt = doc.data()['createdAt'];
          return createdAt is Timestamp ? createdAt.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
        }

        // WhatsApp-style feed: one row per person, with that person's active
        // statuses grouped together and the newest update shown first.
        final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final doc in activeStatuses) {
          final ownerUid = (doc.data()['ownerUid'] ?? '').toString();
          if (ownerUid.isEmpty) continue;
          grouped.putIfAbsent(ownerUid, () => <QueryDocumentSnapshot<Map<String, dynamic>>>[]).add(doc);
        }
        for (final items in grouped.values) {
          items.sort((a, b) => statusDate(b).compareTo(statusDate(a)));
        }

        final mine = grouped.remove(uid) ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final otherGroups = grouped.entries.toList()
          ..sort((a, b) => statusDate(b.value.first).compareTo(statusDate(a.value.first)));

        String timeLabel(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
          final date = statusDate(doc);
          if (date.millisecondsSinceEpoch == 0) return 'Just now';
          final difference = DateTime.now().difference(date);
          if (difference.inMinutes < 1) return 'Just now';
          if (difference.inHours < 1) return '${difference.inMinutes} minutes ago';
          if (difference.inDays < 1) return DateFormat.jm().format(date);
          return DateFormat('d MMM, h:mm a').format(date);
        }

        Widget myStatusAvatar({required bool hasStatus}) {
          return StreamBuilder<DatabaseEvent>(
            stream: ConnectXDatabase.instance.ref('PublicUsers').child(uid).onValue,
            builder: (context, profileSnapshot) {
              final profile = profileSnapshot.data?.snapshot;
              final photoUrl = profile?.child('photoUrl').value?.toString() ??
                  FirebaseAuth.instance.currentUser?.photoURL ?? '';
              final avatar = CircleAvatar(
                radius: 27,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty ? const Icon(Icons.person_outline_rounded) : null,
              );
              return Stack(clipBehavior: Clip.none, children: [
                if (hasStatus)
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF25D366), width: 2.5),
                    ),
                    child: avatar,
                  )
                else
                  avatar,
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 21,
                    height: 21,
                    decoration: BoxDecoration(
                      color: const Color(0xFF008069),
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                    child: const Icon(Icons.add, size: 15, color: Colors.white),
                  ),
                ),
              ]);
            },
          );
        }

        Widget statusAvatar(
          QueryDocumentSnapshot<Map<String, dynamic>> latest, {
          required bool own,
        }) {
          final data = latest.data();
          final photoUrl = (data['userPhotoUrl'] ?? '').toString();
          final avatar = CircleAvatar(
            radius: 27,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            child: photoUrl.isEmpty
                ? Icon((data['mediaType'] ?? 'text') == 'video'
                    ? Icons.videocam_rounded
                    : (data['mediaType'] ?? 'text') == 'image'
                        ? Icons.image_rounded
                        : Icons.text_fields_rounded)
                : null,
          );
          if (own) return myStatusAvatar(hasStatus: true);
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: latest.reference.collection('views').doc(uid).snapshots(),
            builder: (context, viewSnapshot) {
              final viewed = viewSnapshot.data?.exists == true;
              final ringColor = viewed ? Colors.grey.shade500 : const Color(0xFF25D366);
              return Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: viewed ? 1.5 : 2.5),
                ),
                child: avatar,
              );
            },
          );
        }

        Widget statusRow({
          required List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
          required bool own,
        }) {
          final latest = items.first;
          final data = latest.data();
          final name = own ? 'My status' : (data['userName'] ?? 'ConnectX user').toString();
          final preview = own
              ? (items.length == 1 ? 'Tap to view your status' : '${items.length} updates · Tap to view')
              : '${items.length} updates · ${timeLabel(latest)}';
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            leading: statusAvatar(latest, own: own),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: own
                ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: latest.reference.collection('views').snapshots(),
                    builder: (_, views) => Text(
                      views.hasData
                          ? 'Seen by ${views.data!.docs.length} · 24-hour status'
                          : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: own
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: 'Status options',
                        onSelected: (value) async {
                          if (value == 'views') {
                            await _showViewers(context, latest);
                          } else if (value == 'delete') {
                            try {
                              await latest.reference.delete();
                            } catch (error) {
                              if (context.mounted) {
                                showConnectXErrorDialog(context, 'Status could not be deleted. Please try again.');
                              }
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'views', child: Text('View seen list')),
                          PopupMenuItem(value: 'delete', child: Text('Delete latest status')),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Add status',
                        icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF008069)),
                        onPressed: () => _create(context),
                      ),
                    ],
                  )
                : null,
            onTap: () => _viewGroup(context, items, uid),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 90),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Status',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            if (mine.isEmpty)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                leading: myStatusAvatar(hasStatus: false),
                title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Tap to add a status update'),
                onTap: () => _create(context),
                trailing: IconButton(
                  tooltip: 'Create status',
                  icon: const Icon(Icons.camera_alt_outlined),
                  onPressed: () => _create(context),
                ),
              )
            else
              statusRow(items: mine, own: true),
            const Divider(height: 24, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Recent updates',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            if (otherGroups.isEmpty)
              const _SectionEmptyState(
                icon: Icons.circle_outlined,
                title: 'No recent updates',
                description: 'New status updates from ConnectX users will appear here automatically.',
              )
            else
              ...otherGroups.map((group) => statusRow(
                    items: group.value,
                    own: false,
                  )),
            const Divider(height: 28, indent: 16, endIndent: 16),
            const _ChannelsPanel(),
          ],
        );
      },
    );
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
      showConnectXErrorDialog(context, 'Community could not be created. Please try again.');
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
              final data = snap.data?.data() ?? <String, dynamic>{};
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
                        showConnectXErrorDialog(context, 'Membership could not be updated. Please try again.');
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
              final community = membership.data?.data() ?? <String, dynamic>{};
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
              final data = snap.data?.data() ?? <String, dynamic>{};
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
                        showConnectXErrorDialog(context, 'Your post could not be published. Please try again.');
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
                    showConnectXErrorDialog(context, 'Channel membership could not be updated. Please try again.');
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

  Future<void> _startCall(BuildContext context, User1 person, bool video) async {
    try {
      final callId = FirebaseFirestore.instance.collection('calls').doc().id;
      await Navigator.of(context).pushNamed('/call', arguments: {
        'callId': callId,
        'peerUid': person.key,
        'peerName': person.name,
        'isCaller': true,
        'isVideo': video,
      });
    } catch (error) {
      debugPrint('ConnectX start call failed: $error');
      if (context.mounted) {
        showConnectXErrorDialog(context, 'Could not start this call. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final contacts = users.where((person) => person.key != uid).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text('Start a call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        if (contacts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('ConnectX users will appear here when available.'),
          )
        else
          ...contacts.map((person) => ListTile(
            leading: CircleAvatar(
              backgroundImage: person.photoUrl.isNotEmpty ? NetworkImage(person.photoUrl) : null,
              child: person.photoUrl.isEmpty
                  ? Text(person.name.isNotEmpty ? person.name[0].toUpperCase() : 'C')
                  : null,
            ),
            title: Text(person.name),
            subtitle: Text(person.online ? 'Online' : '@${person.username}'),
            trailing: Wrap(spacing: 0, children: [
              IconButton(
                tooltip: 'Voice call',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => _startCall(context, person, false),
              ),
              IconButton(
                tooltip: 'Video call',
                icon: const Icon(Icons.videocam_outlined),
                onPressed: () => _startCall(context, person, true),
              ),
            ]),
          )),
        const Divider(height: 24),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('Recent calls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('calls')
              .where('participants', arrayContains: uid).snapshots(),
          builder: (context, directSnapshot) {
            if (directSnapshot.hasError) {
              debugPrint('ConnectX calls query failed: ${directSnapshot.error}');
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Text('Call history is temporarily unavailable. You can still call a contact above.'),
              );
            }
            if (!directSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final directCalls = directSnapshot.data!.docs.toList()
              ..sort((a, b) {
                final aa = a.data()['createdAt'], bb = b.data()['createdAt'];
                return (bb is Timestamp ? bb : Timestamp(0, 0))
                    .compareTo(aa is Timestamp ? aa : Timestamp(0, 0));
              });
            return Column(children: directCalls.map((doc) {
              final data = doc.data();
              final incoming = data['calleeUid'] == uid;
              final video = data['type'] == 'video';
              final peerName = (incoming ? data['callerName'] : data['calleeName'])?.toString() ?? 'ConnectX user';
              final ringing = data['status'] == 'ringing' && incoming;
              final peerUid = (incoming ? data['callerUid'] : data['calleeUid'])?.toString() ?? '';
              final person = contacts.where((u) => u.key == peerUid).cast<User1?>().firstWhere(
                (u) => u != null, orElse: () => null);
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: person?.photoUrl.isNotEmpty == true ? NetworkImage(person!.photoUrl) : null,
                  child: person?.photoUrl.isNotEmpty == true ? null : Icon(video ? Icons.videocam : Icons.call),
                ),
                title: Text(peerName),
                subtitle: Text(ringing ? 'Incoming ${video ? 'video' : 'voice'} call' :
                    '${incoming ? 'Incoming' : 'Outgoing'} · ${data['status'] ?? 'unknown'}'),
                trailing: ringing ? IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () => Navigator.of(context).pushNamed('/call', arguments: {
                    'callId': doc.id, 'peerUid': peerUid, 'peerName': peerName,
                    'isCaller': false, 'isVideo': video,
                  }),
                ) : null,
              );
            }).toList());
          },
        ),
        const Divider(height: 24),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('Group calls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('groupCalls')
              .where('participants', arrayContains: uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('ConnectX group calls query failed: ${snapshot.error}');
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Text('Group call history is temporarily unavailable.'),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snapshot.data!.docs.toList()
              ..sort((a, b) {
                final aa = a.data()['createdAt'], bb = b.data()['createdAt'];
                return (bb is Timestamp ? bb : Timestamp(0, 0))
                    .compareTo(aa is Timestamp ? aa : Timestamp(0, 0));
              });
            if (docs.isEmpty) return const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No group calls yet.'),
            );
            return Column(children: docs.map((doc) {
              final data = doc.data();
              final expiry = data['expiresAt'];
              final active = data['status'] == 'active' &&
                  expiry is Timestamp && expiry.toDate().isAfter(DateTime.now());
              final type = data['type'] == 'video' ? 'Video' : 'Voice';
              return ListTile(
                leading: CircleAvatar(child: Icon(type == 'Video' ? Icons.video_call : Icons.groups)),
                title: Text((data['groupName'] ?? 'Group call').toString()),
                subtitle: Text('$type group call · ${active ? 'Active' : (data['status'] ?? 'Ended')}'),
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
            }).toList());
          },
        ),
      ],
    );
  }
}

class _StatusStoryViewer extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> statuses;
  final String viewerUid;

  const _StatusStoryViewer({
    required this.statuses,
    required this.viewerUid,
  });

  @override
  State<_StatusStoryViewer> createState() => _StatusStoryViewerState();
}

class _StatusStoryViewerState extends State<_StatusStoryViewer> {
  late final PageController _pageController;
  late final Future<String?>? _authToken;
  Timer? _progressTimer;
  int _index = 0;
  double _progress = 0;
  DateTime _startedAt = DateTime.now();

  QueryDocumentSnapshot<Map<String, dynamic>> get _current => widget.statuses[_index];

  Duration get _duration {
    final type = (_current.data()['mediaType'] ?? 'text').toString();
    return Duration(seconds: type == 'video' ? 30 : 7);
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _authToken = FirebaseAuth.instance.currentUser?.getIdToken();
    _markViewed(0);
    _startProgress();
  }

  Future<void> _markViewed(int index) async {
    final doc = widget.statuses[index];
    if (doc.data()['ownerUid'] == widget.viewerUid) return;
    final viewRef = doc.reference.collection('views').doc(widget.viewerUid);
    try {
      final existing = await viewRef.get();
      if (!existing.exists) {
        await viewRef.set({
          'viewerUid': widget.viewerUid,
          'viewedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (error) {
      debugPrint('ConnectX status seen marker failed: $error');
    }
  }

  void _startProgress() {
    _progressTimer?.cancel();
    _startedAt = DateTime.now();
    _progress = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_startedAt).inMilliseconds;
      final nextProgress = (elapsed / _duration.inMilliseconds).clamp(0.0, 1.0);
      if (nextProgress >= 1) {
        if (_index < widget.statuses.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          Navigator.of(context).pop();
        }
        timer.cancel();
        return;
      }
      setState(() => _progress = nextProgress);
    });
  }

  void _changePage(int nextIndex) {
    setState(() => _index = nextIndex);
    _markViewed(nextIndex);
    _startProgress();
  }

  void _step(int direction) {
    final next = _index + direction;
    if (next < 0) {
      _pageController.animateToPage(0, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } else if (next >= widget.statuses.length) {
      Navigator.of(context).pop();
    } else {
      _pageController.animateToPage(next, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  String _mediaUrl(String raw, String token) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'auth': token,
    }).toString();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _current.data();
    final ownerName = (data['userName'] ?? 'ConnectX user').toString();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ownerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text(
              data['createdAt'] is Timestamp
                  ? DateFormat.jm().format((data['createdAt'] as Timestamp).toDate())
                  : 'Just now',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Close status',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: Row(
              children: List.generate(widget.statuses.length, (index) {
                final value = index < _index ? 1.0 : index == _index ? _progress : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final width = MediaQuery.of(context).size.width;
                _step(details.localPosition.dx < width * .35 ? -1 : 1);
              },
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.statuses.length,
                onPageChanged: _changePage,
                itemBuilder: (context, index) {
                  final story = widget.statuses[index].data();
                  final storyType = (story['mediaType'] ?? 'text').toString();
                  final storyUrl = story['mediaUrl']?.toString();
                  final storyText = (story['statusText'] ?? '').toString();
                  if (storyType == 'image' && storyUrl != null) {
                    return FutureBuilder<String?>(
                      future: _authToken,
                      builder: (context, tokenSnapshot) {
                        if (!tokenSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        }
                        return Center(
                          child: Image.network(
                            _mediaUrl(storyUrl, tokenSnapshot.data!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Text(
                              'Unable to load photo',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      },
                    );
                  }
                  if (storyType == 'video' && storyUrl != null) {
                    return FutureBuilder<String?>(
                      future: _authToken,
                      builder: (context, tokenSnapshot) {
                        if (!tokenSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        }
                        return Center(child: _StatusVideoPlayer(url: _mediaUrl(storyUrl, tokenSnapshot.data!)));
                      },
                    );
                  }
                  return Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(32),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF075E54), Color(0xFF128C7E), Color(0xFF202C33)],
                      ),
                    ),
                    child: Text(
                      storyText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusVideoPlayer extends StatefulWidget {
  final String url;
  const _StatusVideoPlayer({required this.url});

  @override
  State<_StatusVideoPlayer> createState() => _StatusVideoPlayerState();
}

class _StatusVideoPlayerState extends State<_StatusVideoPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialized;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialized = _controller.initialize().then((_) {
      _controller.setLooping(true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialized,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('This video could not be played.'),
        );
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          IconButton(
            iconSize: 42,
            onPressed: () {
              setState(() {
                if (_controller.value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
              });
            },
            icon: Icon(_controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
          ),
        ]);
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
