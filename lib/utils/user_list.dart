import 'package:Chat/main.dart';
import 'package:Chat/models/message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../chat_screen.dart';
import '../models/User.dart';

class UserList extends StatefulWidget {
  final List<User1> users;
  final bool wantChats;

  const UserList({super.key, required this.users, required this.wantChats});

  @override
  State<UserList> createState() => UserListState();
}

class UserListState extends State<UserList> {
  final Map<String, Message?> _latestMessages = {};
  final Map<String, int> _unreadCounts = {};

  @override
  void initState() {
    super.initState();
    _refreshPreviews();
  }

  @override
  void didUpdateWidget(covariant UserList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wantChats) _refreshPreviews();
  }

  Future<void> _refreshPreviews() async {
    if (!widget.wantChats) return;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || widget.users.isEmpty) return;

    final latest = <String, Message?>{};
    final unread = <String, int>{};
    await Future.wait(widget.users.map((user) async {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('messages')
            .doc(assignUsers(currentUid, user.key))
            .collection('chats')
            .orderBy('timestamp', descending: true)
            .limit(10)
            .get();
        final messages = snapshot.docs.map(Message.fromSnapshot).toList();
        latest[user.key] = messages.isEmpty ? null : messages.first;
        unread[user.key] = messages.where((message) =>
            !message.isRead && message.sender != currentUid).length;
      } catch (_) {
        latest[user.key] = null;
        unread[user.key] = 0;
      }
    }));

    if (!mounted) return;
    setState(() {
      _latestMessages
        ..clear()
        ..addAll(latest);
      _unreadCounts
        ..clear()
        ..addAll(unread);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      itemCount: widget.users.length,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, index) {
        final user = widget.users[index];
        if (user.key == currentUid) return const SizedBox.shrink();

        final latest = _latestMessages[user.key];
        final unread = _unreadCounts[user.key] ?? 0;
        final preview = latest?.message ??
            (widget.wantChats ? 'Tap to start chatting' : '@${user.username}');
        final timestamp = latest == null
            ? ''
            : DateFormat('h:mm a').format(
                DateTime.fromMillisecondsSinceEpoch(latest.timestamp),
              );

        return InkWell(
          onTap: () async {
            currentRoute = '/chat';
            await Navigator.of(context).pushNamed('/chat', arguments: user);
            if (mounted) _refreshPreviews();
          },
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundImage:
                          user.photoUrl.isNotEmpty ? NetworkImage(user.photoUrl) : null,
                      child: user.photoUrl.isEmpty
                          ? Text(user.username.substring(0, 1).toUpperCase())
                          : null,
                    ),
                    if (user.online)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                          color: unread > 0
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.wantChats)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (timestamp.isNotEmpty)
                          Text(
                            timestamp,
                            style: TextStyle(
                              fontSize: 11,
                              color: unread > 0
                                  ? const Color(0xFF25D366)
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (unread > 0) ...[
                          const SizedBox(height: 5),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFF25D366),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
