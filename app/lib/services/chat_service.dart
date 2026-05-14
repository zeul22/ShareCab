import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/chat_message.dart';
import '../utils/api_config.dart';

typedef AsyncTokenGetter = Future<String?> Function();

/// Per-group chat backed by socket.io for live delivery + REST for the
/// initial history fetch. One [ChatService] is constructed per group session
/// (instantiated by the screen that opens the chat) — its lifetime is bound
/// to the screen and disposed when the rider navigates away.
///
/// Wire format:
///   - GET  /api/chats/:groupId           → { messages: [...] }
///   - POST /api/chats/:groupId           → { message: {...} }
///   - socket: 'group:subscribe' groupId  → join group room (after auth)
///   - socket: 'chat:message'             → new message broadcast
///   - socket: 'chat:reset'  { groupId }  → group composition changed,
///                                          drop local history.
class ChatService extends ChangeNotifier {
  final String groupId;
  final AsyncTokenGetter _tokenGetter;
  final String _root;
  final http.Client _httpClient;
  io.Socket? _socket;

  final List<ChatMessage> _messages = [];
  bool _connected = false;
  String? _error;

  // Other-rider typing pips. Keyed by userId so repeated typing events
  // from the same person extend their entry instead of stacking. We
  // auto-expire each entry ~4s after the last event so a typing pip
  // never sticks if the rider closes the app mid-message.
  final Map<String, _TypingEntry> _typing = {};
  // Timer that prunes expired _typing entries and notifies listeners.
  Timer? _typingSweep;
  // Throttle: outgoing 'chat:typing start' is emitted at most once every
  // _typingThrottle while the local user keeps typing. A 'stop' is sent
  // shortly after they pause. Reduces socket chatter on long messages.
  DateTime? _lastLocalTypingEmit;
  Timer? _localTypingStopTimer;
  static const Duration _typingThrottle = Duration(milliseconds: 1500);
  static const Duration _typingExpire = Duration(seconds: 4);

  ChatService({
    required this.groupId,
    required AsyncTokenGetter tokenGetter,
    http.Client? httpClient,
    String? apiRoot,
    String? socketRoot,
  })  : _tokenGetter = tokenGetter,
        _root = apiRoot ?? ApiConfig.apiRoot,
        _httpClient = httpClient ?? http.Client();

  // ---------------------------------------------------------------------------
  // Public surface
  // ---------------------------------------------------------------------------

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isConnected => _connected;
  String? get error => _error;

  /// Other riders currently typing, freshest first. Excludes the local
  /// user — we only ever store entries we receive from the server.
  List<TypingUser> get typingUsers {
    final now = DateTime.now();
    final live = _typing.values.where((e) => now.difference(e.at) < _typingExpire).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return live.map((e) => TypingUser(userId: e.userId, name: e.name)).toList();
  }

  /// Boot the socket and the REST history in parallel. If we awaited
  /// history before opening the socket (~few hundred ms), the
  /// chat:typing listener wouldn't be attached yet — so any pip the
  /// co-rider fires in that window would be silently missed and the
  /// "is typing" indicator would only start working after the rider
  /// backed out + re-entered the chat.
  Future<void> connect() async {
    await Future.wait([_openSocket(), _loadHistory()]);
  }

  /// Called by the chat screen as the local user edits the input. We
  /// throttle outgoing 'start' events to one per [_typingThrottle] and
  /// queue a single 'stop' event ~[_typingExpire] after the last
  /// keystroke. If the user sends or clears, call [stopLocalTyping]
  /// to flush the 'stop' immediately.
  void noteLocalTyping() {
    if (_socket == null || !_connected) {
      if (kDebugMode) {
        debugPrint(
          '[chat-typing] noteLocalTyping skipped: '
          'socket=${_socket != null} connected=$_connected',
        );
      }
      return;
    }
    final now = DateTime.now();
    if (_lastLocalTypingEmit == null ||
        now.difference(_lastLocalTypingEmit!) >= _typingThrottle) {
      _lastLocalTypingEmit = now;
      if (kDebugMode) {
        debugPrint('[chat-typing] emit start group=$groupId');
      }
      _socket!.emit('chat:typing', {'groupId': groupId, 'state': 'start'});
    }
    _localTypingStopTimer?.cancel();
    _localTypingStopTimer = Timer(_typingExpire, stopLocalTyping);
  }

  /// Send an immediate 'stop' (used when the rider sends the message or
  /// clears the input). Safe to call even when not currently typing.
  void stopLocalTyping() {
    _localTypingStopTimer?.cancel();
    _localTypingStopTimer = null;
    if (_lastLocalTypingEmit == null) return;
    _lastLocalTypingEmit = null;
    if (_socket != null && _connected) {
      if (kDebugMode) {
        debugPrint('[chat-typing] emit stop group=$groupId');
      }
      _socket!.emit('chat:typing', {'groupId': groupId, 'state': 'stop'});
    }
  }

  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    // Flush the local typing pip the moment we hand the message off —
    // co-rider's "is typing…" line shouldn't linger after the message
    // they were waiting for has actually arrived.
    stopLocalTyping();
    final token = await _tokenGetter();
    if (token == null) {
      _error = 'Not signed in';
      notifyListeners();
      return;
    }
    try {
      final res = await _httpClient.post(
        Uri.parse('$_root/chats/$groupId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'content': trimmed}),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _error = _decodeError(res, fallback: 'Send failed (${res.statusCode})');
        notifyListeners();
        return;
      }
      // We DON'T add to _messages locally — the socket broadcast loops back
      // here, and that single source of truth keeps ordering consistent
      // with what other riders see.
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Send failed: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _localTypingStopTimer?.cancel();
    _typingSweep?.cancel();
    try {
      // Best-effort tell others we stopped typing before tearing down —
      // otherwise their typing pip lingers for the full expiry window.
      if (_socket != null && _connected && _lastLocalTypingEmit != null) {
        _socket!.emit('chat:typing', {'groupId': groupId, 'state': 'stop'});
      }
      _socket?.emit('group:unsubscribe', groupId);
    } catch (_) {/* ignore — socket may already be closed */}
    _socket?.dispose();
    _httpClient.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _loadHistory() async {
    final token = await _tokenGetter();
    if (token == null) return;
    try {
      final res = await _httpClient.get(
        Uri.parse('$_root/chats/$groupId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['messages'] as List?) ?? const [];
      _messages
        ..clear()
        ..addAll(list
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson));
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('chat history fetch failed: $e');
    }
  }

  Future<void> _openSocket() async {
    final token = await _tokenGetter();
    if (token == null) return;

    // ApiConfig.apiRoot is "{base}/api" — strip the suffix so socket.io
    // connects to the root server URL (Express + socket.io share the
    // same HTTP server).
    final socketRoot = _root.endsWith('/api')
        ? _root.substring(0, _root.length - 4)
        : _root;

    _socket = io.io(
      socketRoot,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          // CRITICAL: bypass socket_io_client's Manager cache. Without
          // this, ChatService and ChatUnreadService both call
          // io.io('http://host:port') and get the *same* underlying
          // Socket back (the cache key normalization treats path ''
          // and '/' as different, so the sameNamespace guard misses
          // and the cached Manager is reused). When this screen
          // dispose()s its socket, it closes the shared Manager's
          // WebSocket — taking ChatUnreadService's connection down
          // with it, which is why the unread badge stopped updating
          // after the rider backed out of chat. enableForceNew()
          // guarantees a fresh Manager + Socket so the two services
          // are truly independent.
          .enableForceNew()
          .setAuth({'token': token})
          .build(),
    );

    _socket!
      ..onConnect((_) {
        _connected = true;
        // Server-side group:subscribe is membership-checked, so this is a
        // safe one-shot; if we're not a member the room join is silently
        // refused and we'll stay on REST-loaded history.
        _socket!.emit('group:subscribe', groupId);
        notifyListeners();
      })
      ..onDisconnect((_) {
        _connected = false;
        notifyListeners();
      })
      ..on('chat:message', _handleIncomingMessage)
      ..on('chat:reset', _handleReset)
      ..on('chat:typing', _handleIncomingTyping);

    _socket!.connect();
  }

  void _handleIncomingMessage(dynamic raw) {
    if (raw is! Map) return;
    try {
      final msg = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
      // Dedup on _id — the sender of a message gets it back via socket too,
      // but we never appended it locally on send (see sendMessage), so
      // adding here is correct. Still defend against duplicate emits.
      if (_messages.any((m) => m.id == msg.id)) return;
      _messages.add(msg);
      // A delivered message implies the sender has stopped typing —
      // drop any pending pip for them so the bubble and the pip don't
      // both render at once.
      _typing.remove(msg.senderId);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('chat:message parse failed: $e');
    }
  }

  void _handleIncomingTyping(dynamic raw) {
    if (kDebugMode) debugPrint('[chat-typing] recv raw=$raw');
    if (raw is! Map) return;
    try {
      final uid = (raw['userId'] as String?) ?? '';
      if (uid.isEmpty) return;
      final state = (raw['state'] as String?) ?? 'start';
      if (state == 'stop') {
        if (_typing.remove(uid) != null) notifyListeners();
        return;
      }
      final rawName = (raw['name'] as String? ?? '').trim();
      final name = rawName.isEmpty ? 'Co-rider' : rawName;
      _typing[uid] = _TypingEntry(uid, name, DateTime.now());
      _ensureTypingSweep();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[chat-typing] parse failed: $e');
    }
  }

  // One periodic sweep evicts expired pips and notifies once. We only
  // start the timer lazily on first incoming typing event and let it
  // self-cancel once no pips remain — quiet chats don't pay the wakeup
  // cost.
  void _ensureTypingSweep() {
    if (_typingSweep != null) return;
    _typingSweep = Timer.periodic(const Duration(milliseconds: 800), (_) {
      final now = DateTime.now();
      final before = _typing.length;
      _typing.removeWhere((_, e) => now.difference(e.at) >= _typingExpire);
      if (_typing.isEmpty) {
        _typingSweep?.cancel();
        _typingSweep = null;
      }
      if (_typing.length != before) notifyListeners();
    });
  }

  void _handleReset(dynamic raw) {
    // A rider left or a new one joined — backend wiped the history. Mirror
    // that locally so a freshly-joined third rider doesn't see the prior
    // pair's conversation.
    _messages.clear();
    notifyListeners();
  }

  String _decodeError(http.Response res, {required String fallback}) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final m = body['error'] as String?;
      if (m != null) return m;
    } catch (_) {/* fall through */}
    return fallback;
  }
}

/// One co-rider currently typing. Surfaced to the chat screen so it can
/// render "Asha is typing…" beneath the last bubble.
class TypingUser {
  final String userId;
  final String name;
  const TypingUser({required this.userId, required this.name});
}

class _TypingEntry {
  final String userId;
  final String name;
  final DateTime at;
  _TypingEntry(this.userId, this.name, this.at);
}
