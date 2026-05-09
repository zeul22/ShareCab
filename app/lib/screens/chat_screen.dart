import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Per-group coordination chat. Owns its own [ChatService] for the
/// duration the screen is mounted — the service connects on init, sends
/// `group:subscribe` after socket auth, and disposes its socket when this
/// screen pops.
///
/// Privacy: when a rider leaves OR a new rider joins, the backend wipes
/// the message store and emits `chat:reset`; the service clears its
/// local cache and the empty state takes over here.
class ChatScreen extends StatefulWidget {
  /// Match group id — the chat is scoped to it. Pushed via Navigator
  /// arguments from RideConfirmationScreen.
  final String groupId;

  const ChatScreen({super.key, required this.groupId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _chat;
  late final TextEditingController _input;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
    _scroll = ScrollController();
    final auth = context.read<AuthService>();
    _chat = ChatService(
      groupId: widget.groupId,
      tokenGetter: auth.accessTokenForApi,
    );
    _chat.addListener(_onChatChanged);
    _chat.connect();
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _chat.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Auto-scroll to the newest message on every state change. We delay one
  /// frame so the ListView has actually laid out the new tile before
  /// jumping to the bottom.
  void _onChatChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _chat.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = context.watch<AuthService>().user?.id;
    // If the rider is no longer in any group (cancelled / completed), back
    // out — the chat is meaningless without an active group.
    final flow = context.watch<RideFlowState>();
    if (flow.activeRide == null && flow.proposals.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Co-rider chat'),
        actions: [
          // Tiny connection-state pip so it's obvious when realtime is
          // working vs the fallback REST-only state.
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: _chat.isConnected ? 'Live' : 'Connecting…',
              child: Icon(
                _chat.isConnected ? Icons.wifi : Icons.wifi_off,
                size: 18,
                color: _chat.isConnected ? AppTheme.brand : Colors.black38,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: _chat.messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: _chat.messages.length,
                      itemBuilder: (_, i) {
                        final m = _chat.messages[i];
                        return _Bubble(message: m, isMine: m.isFromMe(myUserId));
                      },
                    ),
            ),
            if (_chat.error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF2F2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  _chat.error!,
                  style: const TextStyle(color: Color(0xFFB00020), fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message…',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppTheme.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _send,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.black26),
            SizedBox(height: 12),
            Text(
              'Say hi to your co-rider',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Coordinate the pickup spot or share a landmark.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const _Bubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isMine ? AppTheme.brand : const Color(0xFFF1F3F4);
    final fg = isMine ? Colors.white : Colors.black87;
    final tail = isMine
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMine)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 2),
                  child: Text(
                    message.senderName,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: bg, borderRadius: tail),
                child: Text(
                  message.content,
                  style: TextStyle(color: fg, fontSize: 14, height: 1.35),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 8, right: 8),
                child: Text(
                  _hhmm(message.sentAt),
                  style: const TextStyle(color: Colors.black38, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _hhmm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
