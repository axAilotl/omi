import 'dart:math';

import 'package:omi/backend/schema/transcript_segment.dart';

class ConversationCaptureWindow {
  const ConversationCaptureWindow({
    required this.startSeconds,
    required this.endSeconds,
  });

  final int startSeconds;
  final int endSeconds;

  static bool hasServerSpeechProof(List<TranscriptSegment> segments) =>
      segments.any((segment) => segment.text.trim().isNotEmpty && segment.end > segment.start);

  factory ConversationCaptureWindow.forCompletion({
    required bool storageAuthoritative,
    required int sessionOriginSeconds,
    required int fallbackStartSeconds,
    required int completionObservedAtSeconds,
    required int conversationBoundarySeconds,
    required List<TranscriptSegment> segments,
  }) {
    if (storageAuthoritative) {
      return ConversationCaptureWindow.fromStorageLifecycle(
        sessionOriginSeconds: sessionOriginSeconds,
        fallbackStartSeconds: fallbackStartSeconds,
        completionObservedAtSeconds: completionObservedAtSeconds,
        conversationBoundarySeconds: conversationBoundarySeconds,
        segments: segments,
      );
    }
    return ConversationCaptureWindow.fromTranscript(
      sessionOriginSeconds: sessionOriginSeconds,
      fallbackStartSeconds: fallbackStartSeconds,
      fallbackEndSeconds: completionObservedAtSeconds,
      segments: segments,
    );
  }

  factory ConversationCaptureWindow.fromTranscript({
    required int sessionOriginSeconds,
    required int fallbackStartSeconds,
    required int fallbackEndSeconds,
    required List<TranscriptSegment> segments,
    int transcriptMarginSeconds = 2,
  }) {
    if (segments.isEmpty) {
      return ConversationCaptureWindow(
        startSeconds: fallbackStartSeconds,
        endSeconds: fallbackEndSeconds,
      );
    }

    final firstSpeechOffset = segments.map((segment) => segment.start).reduce(min).floor();
    final lastSpeechOffset = segments.map((segment) => segment.end).reduce(max).ceil();
    return ConversationCaptureWindow(
      startSeconds: sessionOriginSeconds + firstSpeechOffset - transcriptMarginSeconds,
      endSeconds: sessionOriginSeconds + lastSpeechOffset + transcriptMarginSeconds,
    );
  }

  /// Resolves a storage-authoritative SD-ring session in wall-clock time.
  ///
  /// STT offsets measure only audio submitted to the socket. Pendant VAD and a
  /// disconnected interval both compress that audio clock, so adding the last
  /// transcript offset to [sessionOriginSeconds] can close the durable window
  /// before recovered speech that occurred later in wall-clock time. Natural
  /// completion is observed after [conversationBoundarySeconds] of silence;
  /// that lifecycle edge therefore supplies the missing wall-clock bound.
  factory ConversationCaptureWindow.fromStorageLifecycle({
    required int sessionOriginSeconds,
    required int fallbackStartSeconds,
    required int completionObservedAtSeconds,
    required int conversationBoundarySeconds,
    required List<TranscriptSegment> segments,
    int transcriptMarginSeconds = 5,
  }) {
    if (segments.isEmpty) {
      return ConversationCaptureWindow(
        startSeconds: fallbackStartSeconds,
        endSeconds: completionObservedAtSeconds,
      );
    }

    final transcriptWindow = ConversationCaptureWindow.fromTranscript(
      sessionOriginSeconds: sessionOriginSeconds,
      fallbackStartSeconds: fallbackStartSeconds,
      fallbackEndSeconds: completionObservedAtSeconds,
      segments: segments,
      transcriptMarginSeconds: transcriptMarginSeconds,
    );
    final start = max(
      fallbackStartSeconds,
      sessionOriginSeconds - transcriptMarginSeconds,
    );
    final lifecycleSpeechEnd = completionObservedAtSeconds - conversationBoundarySeconds + transcriptMarginSeconds;
    final end = min(
      completionObservedAtSeconds,
      max(transcriptWindow.endSeconds, lifecycleSpeechEnd),
    );
    return ConversationCaptureWindow(
      startSeconds: start,
      endSeconds: max(start, end),
    );
  }
}
