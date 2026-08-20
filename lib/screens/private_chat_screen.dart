import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../services/private_message_service.dart';
import '../widgets/avatar_renderer.dart';

class PrivateChatScreen extends StatefulWidget {
  const PrivateChatScreen({
    super.key,
    required this.friendId,
    required this.displayName,
    this.avatarUrl,
    this.avatarData,
  });

  final String friendId;
  final String displayName;
  final String? avatarUrl;
  final Map<String, dynamic>? avatarData;

  @override
  State<PrivateChatScreen> createState() =>
      _PrivateChatScreenState();
}

class _PrivateChatScreenState
    extends State<PrivateChatScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final FocusNode _messageFocusNode =
      FocusNode();

  final ScrollController _scrollController =
      ScrollController();

  String? _conversationId;

  Stream<List<Map<String, dynamic>>>? _messageStream;

  bool _loadingConversation = true;

  bool _sendingMessage = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _initializeConversation();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // INITIALISATION DE LA CONVERSATION
  // ===========================================================================

  Future<void> _initializeConversation() async {
    final String? conversationId =
        await PrivateMessageService
            .getOrCreateConversation(
      widget.friendId,
    );

    if (!mounted) {
      return;
    }

    if (conversationId == null ||
        conversationId.isEmpty) {
      setState(() {
        _loadingConversation = false;
        _errorMessage =
            'Impossible d’ouvrir cette conversation privée.';
      });

      return;
    }

    setState(() {
      _conversationId = conversationId;
      _messageStream =
          PrivateMessageService.messageStream(
        conversationId,
      );
      _loadingConversation = false;
      _errorMessage = null;
    });
  }

  // ===========================================================================
  // ENVOI
  // ===========================================================================

  Future<void> _sendMessage() async {
    final String? conversationId =
        _conversationId;

    final String content =
        _messageController.text.trim();

    if (_sendingMessage ||
        conversationId == null ||
        conversationId.isEmpty ||
        content.isEmpty) {
      return;
    }

    setState(() {
      _sendingMessage = true;
    });

    final bool sent =
        await PrivateMessageService.sendMessage(
      conversationId: conversationId,
      content: content,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _sendingMessage = false;
    });

    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’envoyer le message.',
          ),
        ),
      );

      return;
    }

    _messageController.clear();

    _messageFocusNode.requestFocus();

    _scrollToBottom();
  }

  // ===========================================================================
  // SCROLL
  // ===========================================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!_scrollController.hasClients) {
          return;
        }

        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(
            milliseconds: 220,
          ),
          curve: Curves.easeOut,
        );
      },
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: const Color(
        0xff160e09,
      ),
      appBar: AppBar(
        backgroundColor: const Color(
          0xff21150e,
        ),
        foregroundColor: const Color(
          0xffffd27a,
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            _buildHeaderAvatar(),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.displayName,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(
                        0xffffd27a,
                      ),
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Discussion privée',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _buildConversationBody(),
            ),

            _buildComposer(),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CORPS DE LA CONVERSATION
  // ===========================================================================

  Widget _buildConversationBody() {
    if (_loadingConversation) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(
            0xffffc857,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 48,
                color: Colors.orangeAccent,
              ),

              const SizedBox(
                height: 14,
              ),

              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              FilledButton(
                onPressed:
                    _initializeConversation,
                child: const Text(
                  'Réessayer',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Stream<List<Map<String, dynamic>>>?
        stream =
        _messageStream;

    if (stream == null) {
      return const Center(
        child: Text(
          'Conversation indisponible.',
          style: TextStyle(
            color: Colors.white54,
          ),
        ),
      );
    }

    return StreamBuilder<
        List<Map<String, dynamic>>>(
      stream: stream,
      builder: (
        BuildContext context,
        AsyncSnapshot<
                List<Map<String, dynamic>>>
            snapshot,
      ) {
        if (snapshot.connectionState ==
                ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(
                0xffffc857,
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(
                24,
              ),
              child: Text(
                'Impossible de charger les messages.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                ),
              ),
            ),
          );
        }

        final List<Map<String, dynamic>>
            messages =
            snapshot.data ??
                <Map<String, dynamic>>[];

        if (messages.isEmpty) {
          return ListView(
            controller: _scrollController,
            physics:
                const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(
              28,
            ),
            children: [
              const SizedBox(
                height: 90,
              ),

              const Icon(
                Icons.chat_bubble_outline,
                size: 52,
                color: Color(
                  0xffffc857,
                ),
              ),

              const SizedBox(
                height: 15,
              ),

              Text(
                'Commence la discussion avec '
                '${widget.displayName}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  height: 1.4,
                ),
              ),
            ],
          );
        }

        _scrollToBottom();

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            12,
            14,
            12,
            18,
          ),
          itemCount: messages.length,
          itemBuilder: (
            BuildContext context,
            int index,
          ) {
            return _buildMessageBubble(
              messages[index],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // BULLE DE MESSAGE
  // ===========================================================================

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
  ) {
    final bool isMine =
        PrivateMessageService.isMine(
      message,
    );

    final String content =
        message['content']
                ?.toString()
                .trim() ??
            '';

    final String time =
        _formatMessageTime(
      message['created_at'],
    );

    return Align(
      alignment: isMine
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width *
                  0.78,
        ),
        margin: const EdgeInsets.only(
          bottom: 9,
        ),
        padding: const EdgeInsets.fromLTRB(
          13,
          9,
          13,
          7,
        ),
        decoration: BoxDecoration(
          color: isMine
              ? const Color(
                  0xff73451f,
                )
              : const Color(
                  0xff2a1c14,
                ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(
              16,
            ),
            topRight: const Radius.circular(
              16,
            ),
            bottomLeft: Radius.circular(
              isMine ? 16 : 4,
            ),
            bottomRight: Radius.circular(
              isMine ? 4 : 16,
            ),
          ),
          border: Border.all(
            color: isMine
                ? const Color(
                    0xffa86d32,
                  )
                : const Color(
                    0xff4f3321,
                  ),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.35,
              ),
            ),

            const SizedBox(
              height: 4,
            ),

            Text(
              time,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CHAMP DE SAISIE
  // ===========================================================================

  Widget _buildComposer() {
    final bool enabled =
        !_loadingConversation &&
            _errorMessage == null &&
            _conversationId != null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        9,
        10,
        9 +
            MediaQuery.paddingOf(context)
                .bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xff21150e,
        ),
        border: Border(
          top: BorderSide(
            color: Color(
              0xff4a2e1d,
            ),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller:
                  _messageController,
              focusNode:
                  _messageFocusNode,
              enabled: enabled &&
                  !_sendingMessage,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization:
                  TextCapitalization.sentences,
              style: const TextStyle(
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText:
                    'Écrire un message...',
                hintStyle:
                    const TextStyle(
                  color: Colors.white38,
                ),
                counterText: '',
                filled: true,
                fillColor: const Color(
                  0xff160e09,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                  borderSide:
                      BorderSide.none,
                ),
                enabledBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                  borderSide:
                      const BorderSide(
                    color: Color(
                      0xff4d301d,
                    ),
                  ),
                ),
                focusedBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                  borderSide:
                      const BorderSide(
                    color: Color(
                      0xffa86d32,
                    ),
                  ),
                ),
              ),
              onSubmitted: (
                String value,
              ) {
                _sendMessage();
              },
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          SizedBox(
            width: 46,
            height: 46,
            child: FilledButton(
              onPressed: enabled &&
                      !_sendingMessage
                  ? _sendMessage
                  : null,
              style:
                  FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor:
                    const Color(
                  0xff9a5f28,
                ),
                foregroundColor:
                    Colors.white,
                shape:
                    const CircleBorder(),
              ),
              child: _sendingMessage
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // AVATAR DE L'AMI
  // ===========================================================================

  Widget _buildHeaderAvatar() {
    const double size = 38;

    final String avatarUrl =
        widget.avatarUrl?.trim() ?? '';

    if (avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(
          10,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (
              context,
              error,
              stackTrace,
            ) {
              return _buildAvatarFallback(
                size,
              );
            },
          ),
        ),
      );
    }

    final AvatarModel? avatar =
        _buildManualAvatar();

    if (avatar == null) {
      return _buildAvatarFallback(
        size,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        10,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: size,
          maxWidth: size,
          minHeight: size * 1.5,
          maxHeight: size * 1.5,
          child: AvatarRenderer(
            avatar: avatar,
            size: size,
            showFrame: false,
            compactHeadCrop: true,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(
    double size,
  ) {
    final String cleanName =
        widget.displayName.trim();

    final String initial =
        cleanName.isEmpty
            ? '?'
            : cleanName
                .substring(
                  0,
                  1,
                )
                .toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(
          0xff5b3a20,
        ),
        borderRadius: BorderRadius.circular(
          10,
        ),
        border: Border.all(
          color: const Color(
            0xff9b642e,
          ),
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(
            0xffffd27a,
          ),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  AvatarModel? _buildManualAvatar() {
    final Map<String, dynamic>? avatarData =
        widget.avatarData;

    if (avatarData == null) {
      return null;
    }

    if (avatarData['creationMode']
            ?.toString() !=
        'manual') {
      return null;
    }

    final DateTime now =
        DateTime.now();

    try {
      return AvatarModel.fromJson(
        {
          'userId':
              widget.friendId,
          'creationMode':
              'manual',
          'skin':
              avatarData['skin'],
          'hair':
              avatarData['hair'],
          'beard':
              avatarData['beard'],
          'outfit':
              avatarData['outfit'],
          'accessory':
              avatarData['accessory'],
          'glasses':
              avatarData['glasses'],
          'createdAt':
              now.toIso8601String(),
          'updatedAt':
              now.toIso8601String(),
        },
      );
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // HEURE
  // ===========================================================================

  String _formatMessageTime(
    dynamic rawDate,
  ) {
    final DateTime? parsed =
        DateTime.tryParse(
      rawDate?.toString() ?? '',
    );

    if (parsed == null) {
      return '';
    }

    final DateTime local =
        parsed.toLocal();

    final String hour =
        local.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final String minute =
        local.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$hour:$minute';
  }
}
