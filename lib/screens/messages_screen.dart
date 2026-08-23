import 'dart:async';

import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../services/private_message_service.dart';
import '../widgets/avatar_renderer.dart';
import 'private_chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
  });

  @override
  State<MessagesScreen> createState() =>
      _MessagesScreenState();
}

class _MessagesScreenState
    extends State<MessagesScreen> {
  StreamSubscription<List<Map<String, dynamic>>>?
      _activitySubscription;

  bool _loading = true;

  String? _errorMessage;

  List<Map<String, dynamic>> _conversations =
      <Map<String, dynamic>>[];

  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();

    _loadInbox();

    _activitySubscription =
        PrivateMessageService
            .inboxActivityStream()
            .listen(
      (_) {
        _scheduleRealtimeRefresh();
      },
    );
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();

    super.dispose();
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  Future<void> _loadInbox({
    bool showLoader = true,
  }) async {
    if (showLoader &&
        mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final List<Map<String, dynamic>> inbox =
          await PrivateMessageService.getInbox();

      if (!mounted) {
        return;
      }

      setState(() {
        _conversations = inbox;
        _loading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'Impossible de charger les messages.\n$error';
      });
    }
  }

  void _scheduleRealtimeRefresh() {
    if (_refreshScheduled) {
      return;
    }

    _refreshScheduled = true;

    Future<void>.delayed(
      const Duration(
        milliseconds: 180,
      ),
      () async {
        _refreshScheduled = false;

        if (!mounted) {
          return;
        }

        await _loadInbox(
          showLoader: false,
        );
      },
    );
  }

  // ===========================================================================
  // OUVERTURE D'UNE CONVERSATION
  // ===========================================================================

  Future<void> _openConversation(
    Map<String, dynamic> conversation,
  ) async {
    final String conversationId =
        conversation['conversation_id']
                ?.toString()
                .trim() ??
            '';

    final String friendId =
        conversation['friend_id']
                ?.toString()
                .trim() ??
            '';

    if (conversationId.isEmpty ||
        friendId.isEmpty) {
      return;
    }

    final Map<String, dynamic>? profile =
        _asMap(
      conversation['friend_profile'],
    );

    final String displayName =
        profile?['display_name']
                ?.toString()
                .trim() ??
            '';

    final String name =
        displayName.isEmpty
            ? 'Aventurier'
            : displayName;

    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic>? avatarData =
        _asMap(
      profile?['avatar_data'],
    );

    // Dès que le joueur ouvre la conversation depuis l'app Messages,
    // les messages reçus sont considérés comme lus.
    await PrivateMessageService
        .markConversationRead(
      conversationId,
    );

    if (!mounted) {
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          BuildContext context,
        ) {
          return PrivateChatScreen(
            friendId: friendId,
            displayName: name,
            avatarUrl:
                avatarUrl.isEmpty
                    ? null
                    : avatarUrl,
            avatarData:
                avatarData,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadInbox(
      showLoader: false,
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
      backgroundColor:
          const Color(
        0xff100a07,
      ),
      appBar: AppBar(
        backgroundColor:
            const Color(
          0xff21150e,
        ),
        foregroundColor:
            const Color(
          0xffffd27a,
        ),
        centerTitle: true,
        title:
            const Text(
          'MESSAGES',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
            letterSpacing:
                1.2,
          ),
        ),
      ),
      body: SafeArea(
        child:
            RefreshIndicator(
          color:
              const Color(
            0xffffc857,
          ),
          onRefresh:
              _loadInbox,
          child:
              _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        children:
            const [
          SizedBox(
            height: 220,
          ),
          Center(
            child:
                CircularProgressIndicator(
              color:
                  Color(
                0xffffc857,
              ),
            ),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.all(
          24,
        ),
        children: [
          const SizedBox(
            height: 120,
          ),
          const Icon(
            Icons
                .error_outline_rounded,
            size: 48,
            color:
                Colors.orangeAccent,
          ),
          const SizedBox(
            height: 14,
          ),
          Text(
            _errorMessage!,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              color:
                  Colors.white70,
            ),
          ),
          const SizedBox(
            height: 18,
          ),
          Center(
            child:
                FilledButton(
              onPressed:
                  _loadInbox,
              child:
                  const Text(
                'Réessayer',
              ),
            ),
          ),
        ],
      );
    }

    if (_conversations.isEmpty) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.all(
          30,
        ),
        children:
            const [
          SizedBox(
            height: 110,
          ),
          Icon(
            Icons
                .chat_bubble_outline_rounded,
            size: 58,
            color:
                Color(
              0xffffc857,
            ),
          ),
          SizedBox(
            height: 16,
          ),
          Text(
            'Aucune conversation',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  Color(
                0xffffd27a,
              ),
              fontSize: 19,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          SizedBox(
            height: 8,
          ),
          Text(
            'Commence une discussion privée avec un ami pour la retrouver ici.',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  Colors.white54,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        28,
      ),
      itemCount:
          _conversations.length,
      separatorBuilder: (
        BuildContext context,
        int index,
      ) {
        return const SizedBox(
          height: 8,
        );
      },
      itemBuilder: (
        BuildContext context,
        int index,
      ) {
        return _buildConversationCard(
          _conversations[index],
        );
      },
    );
  }

  // ===========================================================================
  // CARTE DE CONVERSATION
  // ===========================================================================

  Widget _buildConversationCard(
    Map<String, dynamic> conversation,
  ) {
    final String friendId =
        conversation['friend_id']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic>? profile =
        _asMap(
      conversation['friend_profile'],
    );

    final String displayName =
        profile?['display_name']
                ?.toString()
                .trim() ??
            '';

    final String name =
        displayName.isEmpty
            ? 'Aventurier'
            : displayName;

    final String lastMessage =
        conversation['last_message']
                ?.toString()
                .trim() ??
            '';

    final int unreadCount =
        _asInt(
      conversation['unread_count'],
    );

    final bool hasUnread =
        unreadCount > 0;

    final String time =
        _formatConversationTime(
      conversation['last_message_at'],
    );

    return Material(
      color:
          hasUnread
              ? const Color(
                  0xff2b1b11,
                )
              : const Color(
                  0xff1c120d,
                ),
      borderRadius:
          BorderRadius.circular(
        18,
      ),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        onTap: () {
          _openConversation(
            conversation,
          );
        },
        child: Container(
          padding:
              const EdgeInsets.all(
            13,
          ),
          decoration:
              BoxDecoration(
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            border:
                Border.all(
              color:
                  hasUnread
                      ? const Color(
                          0xff9b642e,
                        )
                      : const Color(
                          0xff4a2e1d,
                        ),
            ),
          ),
          child: Row(
            children: [
              _buildAvatar(
                profile:
                    profile,
                userId:
                    friendId,
                displayName:
                    name,
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child:
                              Text(
                            name,
                            maxLines:
                                1,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                TextStyle(
                              color:
                                  const Color(
                                0xffffd27a,
                              ),
                              fontSize:
                                  16,
                              fontWeight:
                                  hasUnread
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                            ),
                          ),
                        ),

                        const SizedBox(
                          width: 8,
                        ),

                        Text(
                          time,
                          style:
                              TextStyle(
                            color:
                                hasUnread
                                    ? const Color(
                                        0xffffc857,
                                      )
                                    : Colors.white38,
                            fontSize:
                                10,
                            fontWeight:
                                hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Row(
                      children: [
                        Expanded(
                          child:
                              Text(
                            lastMessage.isEmpty
                                ? 'Nouvelle conversation'
                                : lastMessage,
                            maxLines:
                                1,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                TextStyle(
                              color:
                                  hasUnread
                                      ? Colors.white
                                      : Colors.white54,
                              fontSize:
                                  13,
                              fontWeight:
                                  hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                            ),
                          ),
                        ),

                        if (hasUnread) ...[
                          const SizedBox(
                            width: 9,
                          ),

                          _UnreadBadge(
                            count:
                                unreadCount,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // AVATAR
  // ===========================================================================

  Widget _buildAvatar({
    required Map<String, dynamic>? profile,
    required String userId,
    required String displayName,
  }) {
    const double size =
        58;

    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    if (avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius:
            BorderRadius.circular(
          15,
        ),
        child:
            SizedBox(
          width: size,
          height: size,
          child:
              Image.network(
            avatarUrl,
            fit:
                BoxFit.cover,
            errorBuilder: (
              BuildContext context,
              Object error,
              StackTrace? stackTrace,
            ) {
              return _buildAvatarFallback(
                displayName,
                size: size,
              );
            },
          ),
        ),
      );
    }

    final AvatarModel? avatar =
        _avatarFromProfile(
      profile,
      userId,
    );

    if (avatar == null) {
      return _buildAvatarFallback(
        displayName,
        size: size,
      );
    }

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(
        15,
      ),
      child:
          SizedBox(
        width: size,
        height: size,
        child:
            OverflowBox(
          alignment:
              Alignment.topCenter,
          minWidth:
              size,
          maxWidth:
              size,
          minHeight:
              size * 1.5,
          maxHeight:
              size * 1.5,
          child:
              AvatarRenderer(
            avatar: avatar,
            size: size,
            showFrame:
                false,
            compactHeadCrop:
                true,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(
    String displayName, {
    required double size,
  }) {
    final String cleanName =
        displayName.trim();

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
      alignment:
          Alignment.center,
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff5b3a20,
        ),
        borderRadius:
            BorderRadius.circular(
          15,
        ),
        border:
            Border.all(
          color:
              const Color(
            0xff9b642e,
          ),
        ),
      ),
      child:
          Text(
        initial,
        style:
            const TextStyle(
          color:
              Color(
            0xffffd27a,
          ),
          fontSize:
              22,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }

  AvatarModel? _avatarFromProfile(
    Map<String, dynamic>? profile,
    String userId,
  ) {
    if (profile == null) {
      return null;
    }

    final Map<String, dynamic>? avatarData =
        _asMap(
      profile['avatar_data'],
    );

    if (avatarData == null ||
        avatarData['creationMode']
                ?.toString() !=
            'manual') {
      return null;
    }

    final DateTime now =
        DateTime.now();

    try {
      return AvatarModel.fromJson(
        <String, dynamic>{
          'userId':
              userId.isEmpty
                  ? 'message-user'
                  : userId,
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
  // DATE / HEURE
  // ===========================================================================

  String _formatConversationTime(
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

    final DateTime now =
        DateTime.now();

    final DateTime today =
        DateTime(
      now.year,
      now.month,
      now.day,
    );

    final DateTime messageDay =
        DateTime(
      local.year,
      local.month,
      local.day,
    );

    final int difference =
        today
            .difference(
              messageDay,
            )
            .inDays;

    if (difference == 0) {
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

    if (difference == 1) {
      return 'Hier';
    }

    if (difference >= 2 &&
        difference < 7) {
      const List<String> days =
          <String>[
        'Lun.',
        'Mar.',
        'Mer.',
        'Jeu.',
        'Ven.',
        'Sam.',
        'Dim.',
      ];

      return days[
          local.weekday - 1];
    }

    final String day =
        local.day
            .toString()
            .padLeft(
              2,
              '0',
            );

    final String month =
        local.month
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$day/$month';
  }

  // ===========================================================================
  // OUTILS
  // ===========================================================================

  int _asInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  Map<String, dynamic>? _asMap(
    dynamic value,
  ) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(
        value,
      );
    }

    return null;
  }
}

// =============================================================================
// BADGE NON LU
// =============================================================================

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({
    required this.count,
  });

  final int count;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      constraints:
          const BoxConstraints(
        minWidth: 23,
        minHeight: 23,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 6,
      ),
      alignment:
          Alignment.center,
      decoration:
          const BoxDecoration(
        color:
            Colors.redAccent,
        shape:
            BoxShape.circle,
      ),
      child:
          Text(
        count > 99
            ? '99+'
            : count.toString(),
        style:
            const TextStyle(
          color:
              Colors.white,
          fontSize:
              10,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }
}
