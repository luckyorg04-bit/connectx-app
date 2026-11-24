import 'package:connectx/utils/user_list.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models/user.dart';
import 'services/database_service.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({Key? key}) : super(key: key);

  @override
  State<NewChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<NewChatScreen> {
  final TextEditingController searchController = TextEditingController();
  final List<User1> users = [];
  bool isSearching = false;
  bool _loading = false;
  bool _hasSearched = false;

  Future<void> _searchUsers(String value) async {
    final query = value.trim().toLowerCase();
    if (query.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _hasSearched = false;
      users.clear();
    });

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final usersRef = ConnectXDatabase.instance.ref('PublicUsers');
      final event = await usersRef.orderByChild('username')
          .startAt(query).endAt('$query\uf8ff').once();
      final matches = event.snapshot.children
          .map(User1.getFromSnapshot)
          .where((user) => user.key != currentUid && user.online)
          .toList();

      if (!mounted) return;
      setState(() {
        users
          ..clear()
          ..addAll(matches);
        _hasSearched = true;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User search failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by username',
                ),
                onSubmitted: _searchUsers,
              )
            : const Text('New Chat'),
        actions: [
          IconButton(
            tooltip: isSearching ? 'Close search' : 'Search users',
            icon: Icon(isSearching ? Icons.close : Icons.search_rounded),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                users.clear();
                _hasSearched = false;
                if (!isSearching) searchController.clear();
              });
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : users.isNotEmpty
              ? UserList(users: users, wantChats: false)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      !isSearching
                          ? 'Search for an online ConnectX user to start a chat.'
                          : _hasSearched
                              ? 'No online users found. Check the username and try again.'
                              : 'Enter a username and press Search.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
