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
  final String type;
  final String? mediaUrl;
  final String? fileName;
  final int? durationMs;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;
  final List<String> pollOptions;
  final Map<String, dynamic> pollVotes;
  final int? expiresAt;
  final bool isViewOnce;
  final Map<String, dynamic> viewedBy;

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
    this.type = 'text',
    this.mediaUrl,
    this.fileName,
    this.durationMs,
    this.latitude,
    this.longitude,
    this.contactName,
    this.contactPhone,
    this.pollOptions = const [],
    this.pollVotes = const {},
    this.expiresAt,
    this.isViewOnce = false,
    this.viewedBy = const {},
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
      type: (json['type'] ?? 'text').toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      fileName: json['fileName']?.toString(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      contactName: json['contactName']?.toString(),
      contactPhone: json['contactPhone']?.toString(),
      pollOptions: (json['pollOptions'] as List? ?? const []).map((e) => e.toString()).toList(),
      pollVotes: Map<String, dynamic>.from(json['pollVotes'] ?? const {}),
      expiresAt: (json['expiresAt'] as num?)?.toInt(),
      isViewOnce: json['isViewOnce'] == true,
      viewedBy: Map<String, dynamic>.from(json['viewedBy'] ?? const {}),
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
    'type': type,
    'mediaUrl': mediaUrl,
    'fileName': fileName,
    'durationMs': durationMs,
    'latitude': latitude,
    'longitude': longitude,
    'contactName': contactName,
    'contactPhone': contactPhone,
    'pollOptions': pollOptions,
    'pollVotes': pollVotes,
    'expiresAt': expiresAt,
    'isViewOnce': isViewOnce,
    'viewedBy': viewedBy,
  };

  static Message fromSnapshot(DocumentSnapshot object) {
    final data = object.data() as Map<String, dynamic>? ?? {};
    return Message.fromJson({...data, 'messageId': object.id});
  }
}
