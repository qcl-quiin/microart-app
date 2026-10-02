class NotificationEntry {
  final int? id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;

  const NotificationEntry({
    this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead ? 1 : 0,
    };
  }

  factory NotificationEntry.fromMap(Map<String, dynamic> map) {
    return NotificationEntry(
      id: map['id'] as int?,
      title: map['title'] as String,
      body: map['body'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      isRead: (map['is_read'] as int) == 1,
    );
  }
}