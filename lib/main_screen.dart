import 'dart:async';
import 'package:Chat/models/chat.dart';
import 'package:Chat/utils/user_list.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'main.dart';
import 'models/User.dart';
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
                  _showComingSoon('New group');
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
    const filters = ['All', 'Unread', 'Favorites', 'Groups'];
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
          child: _chatFilter == 'All'
              ? UserList(users: users, key: userListKey, wantChats: true)
              : _SectionEmptyState(
                  icon: _chatFilter == 'Unread'
                      ? Icons.mark_chat_unread_outlined
                      : _chatFilter == 'Favorites'
                          ? Icons.star_border_rounded
                          : Icons.groups_outlined,
                  title: _chatFilter == 'Unread'
                      ? 'No unread chats'
                      : _chatFilter == 'Favorites'
                          ? 'Your favorite chats will appear here'
                          : 'Your group chats will appear here',
                  description: _chatFilter == 'Unread'
                      ? 'Unread conversations will be listed here.'
                      : _chatFilter == 'Favorites'
                          ? 'Star or favorite a conversation to find it quickly.'
                          : 'Create or join a group to start chatting with multiple people.',
                ),
        ),
      ],
    );
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

class _UpdatesTab extends StatelessWidget {
  const _UpdatesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        Text('Status', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                child: const Icon(Icons.person_rounded, size: 30),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                  ),
                  child: const Icon(Icons.add, size: 17, color: Colors.white),
                ),
              ),
            ],
          ),
          title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Tap to add a status update'),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status sharing will be enabled in the next feature stage.')),
          ),
        ),
        const Divider(height: 24),
        Text('Recent updates', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 28),
        const _SectionEmptyState(
          icon: Icons.circle_outlined,
          title: 'No recent updates',
          description: 'When your contacts share a status, it will appear here.',
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.campaign_outlined)),
          title: const Text('Channels', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Discover updates from people and organizations'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Channels will be added in the next feature stage.')),
          ),
        ),
      ],
    );
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
