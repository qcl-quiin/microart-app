class HistoryEntry {
  final int? id;
  final String result;
  final double confidence;
  final String description;
  final DateTime timestamp;
  final String? imageCrop;

  const HistoryEntry({
    this.id,
    required this.result,
    required this.confidence,
    required this.description,
    required this.timestamp,
    this.imageCrop,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'result': result,
      'confidence': confidence,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'image_crop': imageCrop,
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      id: map['id'] as int?,
      result: map['result'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      description: map['description'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      imageCrop: map['image_crop'] as String?,
    );
  }

  bool get isReal => result == 'REAL';
}