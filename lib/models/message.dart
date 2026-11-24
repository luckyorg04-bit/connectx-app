import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String message;
  final bool isRead;
  final int timestamp;
  final String sender;
  final String? messageId;
  final String? replyTo;
  final String? replyToId;
  final bool isEdited;
  final bool isForwarded;
  final Map<String, dynamic> reactions;

  Message({
    required this.message,
    required this.isRead,
    required this.timestamp,
    required this.sender,
    this.messageId,
    this.replyTo,
    this.replyToId,
    this.isEdited = false,
    this.isForwarded = false,
    this.reactions = const {},
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      message: (json['message'] ?? '').toString(),
      isRead: json['isRead'] == true,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      sender: (json['sender'] ?? '').toString(),
      messageId: json['messageId']?.toString(),
      replyTo: json['replyTo']?.toString(),
      replyToId: json['replyToId']?.toString(),
      isEdited: json['isEdited'] == true,
      isForwarded: json['isForwarded'] == true,
      reactions: Map<String, dynamic>.from(json['reactions'] ?? const {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'message': message,
    'isRead': isRead,
    'timestamp': timestamp,
    'sender': sender,
    'messageId': messageId,
    'replyTo': replyTo,
    'replyToId': replyToId,
    'isEdited': isEdited,
    'isForwarded': isForwarded,
    'reactions': reactions,
  };

  static Message fromSnapshot(DocumentSnapshot object) {
    final data = object.data() as Map<String, dynamic>? ?? {};
    return Message.fromJson({...data, 'messageId': object.id});
  }
}
