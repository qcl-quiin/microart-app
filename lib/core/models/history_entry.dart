class HistoryEntry {
  final int? id;
  final String result; // 'REAL' hoặc 'FAKE'
  final double confidence; // điểm % của kết luận
  final String description;
  final DateTime timestamp;

  const HistoryEntry({
    this.id,
    required this.result,
    required this.confidence,
    required this.description,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'result': result,
      'confidence': confidence,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      id: map['id'] as int?,
      result: map['result'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      description: map['description'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  bool get isReal => result == 'REAL';
}
