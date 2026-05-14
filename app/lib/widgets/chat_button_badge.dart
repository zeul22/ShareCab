import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_unread_service.dart';

/// Small overlay badge that renders an unread-message count on top of
/// whatever chat-launching widget the caller passes in. Hides itself
/// when the count is zero so screens with no co-rider chat (solo
/// trips) look unchanged.
///
/// Subscribes to [ChatUnreadService] via Provider, so the badge updates
/// the moment a co-rider's message arrives even if the user is on a
/// different screen than the chat itself.
class ChatButtonBadge extends StatelessWidget {
  /// The group whose unread count drives the badge. Pass the same
  /// groupId that the chat button navigates to.
  final String groupId;

  /// The underlying chat-launch widget (IconButton, FilledButton, etc).
  final Widget child;

  /// Where the count sits relative to [child]. Defaults to the top-right
  /// corner, which fits both AppBar IconButtons and inline buttons.
  final AlignmentGeometry alignment;

  const ChatButtonBadge({
    super.key,
    required this.groupId,
    required this.child,
    this.alignment = const Alignment(0.9, -0.9),
  });

  @override
  Widget build(BuildContext context) {
    final unread = context.select<ChatUnreadService, int>(
      (s) => s.unreadFor(groupId),
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        child,
        if (unread > 0)
          Align(
            alignment: alignment,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
