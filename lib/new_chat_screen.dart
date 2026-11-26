import 'package:connectx/utils/user_list.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'utils/app_feedback.dart';

import 'models/user.dart';
import 'services/database_service.dart';
import 'services/phone_lookup_service.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({Key? key}) : super(key: key);

  @override
  State<NewChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<NewChatScreen> {
  final TextEditingController searchController = TextEditingController();
  final List<User1> users = [];
  bool _loading = false;
  bool _hasSearched = false;
  String _lastQueryType = 'username';

  bool _looksLikePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7 && digits.length <= 15 &&
        RegExp(r'^[+0-9()\s.-]+$').hasMatch(value);
  }

  Future<void> _searchUsers(String value) async {
    final query = value.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _hasSearched = false;
      users.clear();
      _lastQueryType = _looksLikePhone(query) ? 'phone number' : 'username';
    });

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final List<User1> matches;
      if (_looksLikePhone(query)) {
        final targetUid = await PhoneLookupService.findUid(query);
        if (targetUid == null || targetUid == currentUid) {
          matches = [];
        } else {
          final snapshot = await ConnectXDatabase.instance
              .ref('PublicUsers')
              .child(targetUid)
              .get();
          matches = snapshot.exists ? [User1.getFromSnapshot(snapshot)] : [];
        }
      } else {
        final normalized = query.replaceFirst(RegExp(r'^@'), '').toLowerCase();
        final event = await ConnectXDatabase.instance
            .ref('PublicUsers')
            .orderByChild('username')
            .startAt(normalized)
            .endAt('$normalized\uf8ff')
            .once();
        matches = event.snapshot.children
            .map(User1.getFromSnapshot)
            .where((user) => user.key != currentUid)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        users..clear()..addAll(matches);
        _hasSearched = true;
      });
    } catch (error) {
      debugPrint('ConnectX user search failed: $error');
      if (mounted) {
        showConnectXErrorDialog(context, 'Search could not be completed. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find people'),
        actions: [
          IconButton(
            tooltip: 'Scan ConnectX QR',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => Navigator.of(context).pushNamed('/scan-qr'),
          ),
          if (searchController.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() {
                searchController.clear();
                users.clear();
                _hasSearched = false;
              }),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('Connect with anyone',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Search by ConnectX username or full phone number.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              child: TextField(
                controller: searchController,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: _searchUsers,
                decoration: InputDecoration(
                  hintText: 'Username or phone number',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: _loading ? null : () => _searchUsers(searchController.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerHighest.withOpacity(.55),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: colors.primary, width: 1.5)),
                ),
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (users.isNotEmpty)
              Expanded(child: Column(children: [
                if (_lastQueryType == 'phone number')
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.phone_rounded),
                    title: const Text('Phone number matched'),
                    subtitle: Text(searchController.text.trim()),
                  ),
                Expanded(child: UserList(users: users, wantChats: false)),
              ]))
            else
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76, height: 76,
                          decoration: BoxDecoration(color: colors.primaryContainer, shape: BoxShape.circle),
                          child: Icon(_hasSearched ? Icons.person_search_rounded : Icons.forum_outlined,
                              size: 34, color: colors.onPrimaryContainer),
                        ),
                        const SizedBox(height: 18),
                        Text(_hasSearched ? 'No matching user found' : 'Your next conversation starts here',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          _hasSearched
                              ? 'Check the $_lastQueryType and try again.'
                              : 'Search by username, phone number, or scan a ConnectX QR code.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant, height: 1.45),
                        ),
                        if (_hasSearched) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _searchUsers(searchController.text),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
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
