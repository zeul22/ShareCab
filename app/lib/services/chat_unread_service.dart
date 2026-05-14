import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../utils/api_config.dart';
import 'auth_service.dart';
import 'ride_flow.dart';

typedef AsyncTokenGetter = Future<String?> Function();

/// App-lifetime unread-message counter for the rider's active match
/// group's chat. Independent of [ChatService] (which lives only while
/// the chat screen is mounted) so a rider sitting on the ride
/// confirmation screen still sees the badge update when a co-rider
/// sends a message.
///
/// Wire:
///   - Watches [RideFlowState] for the currently active group id
///     (active ride OR first proposal). When it changes, drops the
///     previous socket subscription and joins the new one.
///   - Listens for the same 'chat:message' broadcast the chat screen
///     listens for, but only to count, never to render.
///   - The chat screen calls [markChatOpened] / [markChatClosed] so
///     incoming messages while the screen is on top don't bump the
///     badge — the user is already reading them.
class ChatUnreadService extends ChangeNotifier {
  final AuthService _auth;
  RideFlowState? _flow;
  final String _root;

  io.Socket? _socket;
  String? _subscribedGroupId;
  String? _openGroupId;

  /// Per-group unread counter. We keep a map (not a single int) so that
  /// switching between an old active ride and a new search keeps each
  /// chat's count distinct until the screens dispose.
  final Map<String, int> _unread = {};

  ChatUnreadService(this._auth, {String? apiRoot})
      : _root = apiRoot ?? ApiConfig.apiRoot {
    _auth.addListener(_onAuthChanged);
  }

  // Re-wired by ChangeNotifierProxyProvider every time RideFlowState
  // rebuilds. Cheap when the value hasn't changed — we only attach
  // listeners when the reference is new.
  void attachFlow(RideFlowState flow) {
    if (identical(_flow, flow)) {
      _syncSubscription();
      return;
    }
    _flow?.removeListener(_onFlowChanged);
    _flow = flow;
    flow.addListener(_onFlowChanged);
    _syncSubscription();
  }

  int unreadFor(String? groupId) {
    if (groupId == null || groupId.isEmpty) return 0;
    return _unread[groupId] ?? 0;
  }

  /// Called from the chat screen's initState. Resets the counter for
  /// this group and suppresses bumps while the screen is on top.
  void markChatOpened(String groupId) {
    _openGroupId = groupId;
    if ((_unread[groupId] ?? 0) > 0) {
      _unread[groupId] = 0;
      notifyListeners();
    }
  }

  void markChatClosed(String groupId) {
    if (_openGroupId == groupId) _openGroupId = null;
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _flow?.removeListener(_onFlowChanged);
    _disposeSocket();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  String? get _activeGroupId {
    final f = _flow;
    if (f == null) return null;
    final active = f.activeRide?.proposal.groupId;
    if (active != null && active.isNotEmpty) return active;
    if (f.proposals.isNotEmpty) {
      final g = f.proposals.first.groupId;
      if (g != null && g.isNotEmpty) return g;
    }
    return null;
  }

  void _onAuthChanged() {
    // Signed out → tear everything down; signed in → re-subscribe if
    // a group is already active.
    if (_auth.user == null) {
      _disposeSocket();
      if (_unread.isNotEmpty) {
        _unread.clear();
        notifyListeners();
      }
    } else {
      _syncSubscription();
    }
  }

  void _onFlowChanged() => _syncSubscription();

  Future<void> _syncSubscription() async {
    final groupId = _activeGroupId;
    if (groupId == _subscribedGroupId) return;
    if (kDebugMode) {
      debugPrint(
        '[chat-unread] sync: prev=$_subscribedGroupId next=$groupId',
      );
    }
    // Leave the prior room (if any) and join the new one. We keep one
    // socket alive across group changes — only the room membership
    // moves.
    final prev = _subscribedGroupId;
    _subscribedGroupId = groupId;
    if (_socket != null && prev != null) {
      try {
        _socket!.emit('group:unsubscribe', prev);
      } catch (_) {/* socket may already be down */}
    }
    if (groupId == null) return;
    if (_auth.user == null) return;
    if (_socket == null) {
      await _openSocket();
    }
    if (_socket != null && _socket!.connected) {
      if (kDebugMode) {
        debugPrint('[chat-unread] emit group:subscribe $groupId (already connected)');
      }
      _socket!.emit('group:subscribe', groupId);
    }
    // If the socket isn't connected yet, onConnect will fire the
    // group:subscribe once the WS handshake completes — see _openSocket.
  }

  Future<void> _openSocket() async {
    final token = await _auth.accessTokenForApi();
    if (token == null) return;
    final socketRoot = _root.endsWith('/api')
        ? _root.substring(0, _root.length - 4)
        : _root;
    if (kDebugMode) {
      debugPrint('[chat-unread] opening socket → $socketRoot');
    }
    _socket = io.io(
      socketRoot,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          // Force a private Manager + Socket so this long-lived service
          // doesn't share with ChatService — see the matching note in
          // chat_service.dart for the cache-key bug we're working around.
          .enableForceNew()
          .setAuth({'token': token})
          .build(),
    );
    _socket!
      ..onConnect((_) {
        final gid = _subscribedGroupId;
        if (kDebugMode) {
          debugPrint(
            '[chat-unread] socket connected; subscribing to group=$gid',
          );
        }
        if (gid != null) _socket!.emit('group:subscribe', gid);
      })
      ..onDisconnect((_) {
        if (kDebugMode) debugPrint('[chat-unread] socket disconnected');
      })
      ..on('chat:message', _handleIncomingMessage)
      ..on('chat:reset', _handleReset);
    _socket!.connect();
  }

  void _handleIncomingMessage(dynamic raw) {
    if (kDebugMode) debugPrint('[chat-unread] recv chat:message raw=$raw');
    if (raw is! Map) return;
    final groupId = (raw['matchGroup'] as String?) ?? '';
    if (groupId.isEmpty) {
      if (kDebugMode) debugPrint('[chat-unread] drop: no matchGroup field');
      return;
    }
    final sender = raw['sender'];
    String senderId = '';
    if (sender is Map) {
      senderId = (sender['_id'] as String?) ?? '';
    } else if (sender is String) {
      senderId = sender;
    }
    final me = _auth.user?.id;
    if (me != null && senderId == me) {
      if (kDebugMode) debugPrint('[chat-unread] drop: own message');
      return;
    }
    // Don't bump while the rider is staring at the chat screen for
    // this same group — they're already reading the message.
    if (_openGroupId == groupId) {
      if (kDebugMode) debugPrint('[chat-unread] drop: chat open for this group');
      return;
    }
    final next = (_unread[groupId] ?? 0) + 1;
    _unread[groupId] = next;
    if (kDebugMode) debugPrint('[chat-unread] bump group=$groupId → $next');
    notifyListeners();
  }

  void _handleReset(dynamic raw) {
    // Group composition changed — backend wiped history. Clear our
    // counter for that group too; the badge shouldn't claim "3 new"
    // when the messages no longer exist.
    if (raw is Map) {
      final gid = (raw['groupId'] as String?) ?? '';
      if (gid.isNotEmpty && _unread.remove(gid) != null) {
        notifyListeners();
      }
    }
  }

  void _disposeSocket() {
    try {
      _socket?.dispose();
    } catch (_) {/* ignore */}
    _socket = null;
    _subscribedGroupId = null;
  }
}
