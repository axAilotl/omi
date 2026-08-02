class ConversationSessionWindow {
  final List<_ConversationSessionBoundary> _pending = [];
  int? _unboundStartSeconds;

  int ensureStarted(int nowSeconds) {
    if (_pending.isNotEmpty) return _pending.first.startedAtSeconds;
    return _unboundStartSeconds ??= nowSeconds;
  }

  int observe({
    required String conversationId,
    required int nowSeconds,
  }) {
    if (_pending.any((entry) => entry.conversationId == conversationId)) {
      return _pending.first.startedAtSeconds;
    }

    final startedAtSeconds = _pending.isEmpty ? (_unboundStartSeconds ?? nowSeconds) : nowSeconds;
    _pending.add(
      _ConversationSessionBoundary(
        conversationId: conversationId,
        startedAtSeconds: startedAtSeconds,
      ),
    );
    _unboundStartSeconds = null;
    return _pending.first.startedAtSeconds;
  }

  /// Reclaims a server-owned conversation after the app process restarts.
  ///
  /// Unlike [observe], which normally receives the first server event for a
  /// newly-created socket session, this path already has an authoritative
  /// server start time. Keeping that boundary is what lets locally recovered
  /// audio from the app-down interval rejoin the same conversation.
  int reclaim({
    required String conversationId,
    required int serverStartedAtSeconds,
    required int nowSeconds,
  }) {
    if (_pending.any((entry) => entry.conversationId == conversationId)) {
      return _pending.first.startedAtSeconds;
    }

    final boundedServerStart =
        serverStartedAtSeconds > 0 && serverStartedAtSeconds <= nowSeconds ? serverStartedAtSeconds : nowSeconds;
    final startedAtSeconds = _pending.isEmpty
        ? [_unboundStartSeconds, boundedServerStart].whereType<int>().reduce((a, b) => a < b ? a : b)
        : nowSeconds;
    _pending.add(
      _ConversationSessionBoundary(
        conversationId: conversationId,
        startedAtSeconds: startedAtSeconds,
      ),
    );
    _unboundStartSeconds = null;
    return _pending.first.startedAtSeconds;
  }

  int complete({
    required String conversationId,
    required int fallbackStartSeconds,
  }) {
    if (_pending.isEmpty) {
      final start = _unboundStartSeconds ?? fallbackStartSeconds;
      _unboundStartSeconds = null;
      return start;
    }

    final completedIndex = _pending.indexWhere((entry) => entry.conversationId == conversationId);
    if (completedIndex < 0) {
      final start = fallbackStartSeconds > 0 ? fallbackStartSeconds : _pending.first.startedAtSeconds;
      _pending.clear();
      _unboundStartSeconds = null;
      return start;
    }

    final start = _pending.first.startedAtSeconds;
    _pending.removeRange(0, completedIndex + 1);
    return start;
  }

  int? get nextStartSeconds => _pending.isEmpty ? null : _pending.first.startedAtSeconds;

  void reset() {
    _pending.clear();
    _unboundStartSeconds = null;
  }
}

class _ConversationSessionBoundary {
  const _ConversationSessionBoundary({
    required this.conversationId,
    required this.startedAtSeconds,
  });

  final String conversationId;
  final int startedAtSeconds;
}
