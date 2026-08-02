import 'package:omi/services/capture/capture_controller.dart';

class CaptureProvider extends CaptureController {
  CaptureProvider({
    super.externalActions,
    super.inProgressConversationFetcher = fetchInProgressConversation,
  });
}
