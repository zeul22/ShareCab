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

  /// Boot order: pull initial history via REST, then open the socket and
  /// subscribe to the group room. Doing REST first so the rider sees the
  /// existing chat instantly even before the socket negotiates.
  Future<void> connect() async {
    await _loadHistory();
    await _openSocket();
  }

  Future<void> sendMessage(String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
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
    try {
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
      ..on('chat:reset', _handleReset);

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
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('chat:message parse failed: $e');
    }
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
