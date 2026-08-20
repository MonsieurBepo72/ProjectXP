import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import 'friend_requests_screen.dart';
import 'friends_screen.dart';
import '../services/friend_service.dart';
import '../services/supabase_service.dart';
import '../services/tavern_service.dart';
import '../widgets/avatar_renderer.dart';

class TavernScreen extends StatefulWidget {
  const TavernScreen({
    super.key,
  });

  @override
  State<TavernScreen> createState() => _TavernScreenState();
}

class _TavernScreenState extends State<TavernScreen> {
  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _messageScrollController =
      ScrollController();

  bool _loadingChannels = true;
  bool _sendingMessage = false;

  int _incomingFriendRequestCount = 0;

  String? _errorMessage;

  List<Map<String, dynamic>> _channels =
      <Map<String, dynamic>>[];

  Map<String, dynamic>? _selectedChannel;

  Stream<List<Map<String, dynamic>>>? _messageStream;

  @override
  void initState() {
    super.initState();
    _loadChannels();
    _refreshFriendRequests();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    try {
      final List<Map<String, dynamic>> channels =
          await TavernService.getChannels();

      if (!mounted) {
        return;
      }

      Map<String, dynamic>? defaultChannel;

      for (final Map<String, dynamic> channel in channels) {
        if (channel['slug']?.toString() == 'comptoir') {
          defaultChannel = channel;
          break;
        }
      }

      if (defaultChannel == null && channels.isNotEmpty) {
        defaultChannel = channels.first;
      }

      final String defaultChannelId =
          defaultChannel?['id']?.toString() ?? '';

      final Stream<List<Map<String, dynamic>>>? defaultStream =
          defaultChannelId.isEmpty
              ? null
              : TavernService.messageStream(
                  defaultChannelId,
                );

      setState(() {
        _channels = channels;
        _selectedChannel = defaultChannel;
        _messageStream = defaultStream;
        _loadingChannels = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingChannels = false;
        _errorMessage =
            'Impossible de charger la Taverne.\n$error';
      });
    }
  }

  void _selectChannel(
    Map<String, dynamic> channel,
  ) {
    final String newChannelId =
        channel['id']?.toString() ?? '';

    final String currentChannelId =
        _selectedChannel?['id']?.toString() ?? '';

    if (newChannelId.isEmpty ||
        newChannelId == currentChannelId) {
      return;
    }

    final Stream<List<Map<String, dynamic>>> newStream =
        TavernService.messageStream(
      newChannelId,
    );

    setState(() {
      _selectedChannel = channel;
      _messageStream = newStream;
    });
  }

  Future<void> _sendMessage() async {
    if (_sendingMessage) {
      return;
    }

    final Map<String, dynamic>? channel =
        _selectedChannel;

    if (channel == null) {
      return;
    }

    final String channelId =
        channel['id']?.toString() ?? '';

    final String content =
        _messageController.text.trim();

    if (channelId.isEmpty || content.isEmpty) {
      return;
    }

    setState(() {
      _sendingMessage = true;
    });

    final bool success =
        await TavernService.sendMessage(
      channelId: channelId,
      content: content,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _sendingMessage = false;
    });

    if (success) {
      _messageController.clear();

      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          _scrollToBottom();
        },
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Impossible d’envoyer le message.',
        ),
      ),
    );
  }

  void _scrollToBottom() {
    if (!_messageScrollController.hasClients) {
      return;
    }

    _messageScrollController.animateTo(
      _messageScrollController.position.maxScrollExtent,
      duration: const Duration(
        milliseconds: 350,
      ),
      curve: Curves.easeOut,
    );
  }

  // ===========================================================================
  // DEMANDES D'AMI
  // ===========================================================================

  Future<void> _refreshFriendRequests() async {
    final List<Map<String, dynamic>> requests =
        await FriendService.getIncomingRequests();

    if (!mounted) {
      return;
    }

    setState(() {
      _incomingFriendRequestCount =
          requests.length;
    });
  }

  Future<void> _openFriends() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          context,
        ) =>
            const FriendsScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshFriendRequests();
  }

  Future<void> _openFriendRequests() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          context,
        ) =>
            const FriendRequestsScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshFriendRequests();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: const Color(
        0xff120b07,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        10,
        8,
        16,
        10,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xff1d120b,
        ),
        border: Border(
          bottom: BorderSide(
            color: Color(
              0xff6f4a29,
            ),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Retour au Hall',
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(
              Icons.arrow_back,
              color: Color(
                0xffffd27a,
              ),
            ),
          ),
          const SizedBox(
            width: 4,
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'LA TAVERNE',
                  style: TextStyle(
                    color: Color(
                      0xffffd27a,
                    ),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                SizedBox(
                  height: 2,
                ),
                Text(
                  'Le lieu de rencontre des aventuriers',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Mes amis',
            onPressed: _openFriends,
            icon: const Icon(
              Icons.group_outlined,
              color: Color(
                0xffffd27a,
              ),
            ),
          ),

          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Demandes d’ami',
                onPressed:
                    _openFriendRequests,
                icon: const Icon(
                  Icons.people_alt_outlined,
                  color: Color(
                    0xffffd27a,
                  ),
                ),
              ),

              if (_incomingFriendRequestCount >
                  0)
                Positioned(
                  right: 2,
                  top: 1,
                  child: IgnorePointer(
                    child: Container(
                      constraints:
                          const BoxConstraints(
                        minWidth: 19,
                        minHeight: 19,
                      ),
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 5,
                      ),
                      alignment:
                          Alignment.center,
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.redAccent,
                        shape:
                            BoxShape.circle,
                        border:
                            Border.all(
                          color:
                              const Color(
                            0xff1d120b,
                          ),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        _incomingFriendRequestCount >
                                99
                            ? '99+'
                            : _incomingFriendRequestCount
                                .toString(),
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontSize: 9,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(
            width: 3,
          ),

          const Icon(
            Icons.local_fire_department,
            color: Color(
              0xffffa742,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loadingChannels) {
      return const Center(
        child: CircularProgressIndicator(),
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
                Icons.error_outline,
                size: 44,
                color: Colors.orangeAccent,
              ),
              const SizedBox(
                height: 14,
              ),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(
                height: 18,
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loadingChannels = true;
                    _errorMessage = null;
                  });

                  _loadChannels();
                },
                child: const Text(
                  'Réessayer',
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_channels.isEmpty) {
      return const Center(
        child: Text(
          'Aucun channel disponible.',
        ),
      );
    }

    return Column(
      children: [
        _buildChannelSelector(),
        Expanded(
          child: _buildSelectedChannel(),
        ),
      ],
    );
  }

  Widget _buildChannelSelector() {
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        color: Color(
          0xff181009,
        ),
        border: Border(
          bottom: BorderSide(
            color: Color(
              0xff4d321d,
            ),
          ),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: _channels.length,
        separatorBuilder: (
          context,
          index,
        ) {
          return const SizedBox(
            width: 8,
          );
        },
        itemBuilder: (
          context,
          index,
        ) {
          final Map<String, dynamic> channel =
              _channels[index];

          final bool selected =
              channel['id'] ==
                  _selectedChannel?['id'];

          final String icon =
              channel['icon']?.toString() ?? '🍺';

          final String name =
              channel['name']?.toString() ??
                  'Channel';

          return InkWell(
            borderRadius: BorderRadius.circular(
              12,
            ),
            onTap: () {
              _selectChannel(
                channel,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: 220,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(
                        0xff49301b,
                      )
                    : const Color(
                        0xff25170e,
                      ),
                borderRadius: BorderRadius.circular(
                  12,
                ),
                border: Border.all(
                  color: selected
                      ? const Color(
                          0xffffc857,
                        )
                      : const Color(
                          0xff5a3a22,
                        ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    icon,
                    style: const TextStyle(
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(
                    width: 7,
                  ),
                  Text(
                    name,
                    style: TextStyle(
                      color: selected
                          ? const Color(
                              0xffffd27a,
                            )
                          : Colors.white70,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedChannel() {
    final Map<String, dynamic>? channel =
        _selectedChannel;

    if (channel == null) {
      return const SizedBox.shrink();
    }

    final String slug =
        channel['slug']?.toString() ?? '';

    if (slug == 'comptoir') {
      return _buildComptoir(
        channel,
      );
    }

    return _buildFutureChannel(
      channel,
    );
  }

  Widget _buildComptoir(
    Map<String, dynamic> channel,
  ) {
    final String channelId =
        channel['id']?.toString() ?? '';

    if (channelId.isEmpty) {
      return const Center(
        child: Text(
          'Channel invalide.',
        ),
      );
    }

    final Stream<List<Map<String, dynamic>>>? messageStream =
        _messageStream;

    if (messageStream == null) {
      return const Center(
        child: Text(
          'Flux du channel indisponible.',
        ),
      );
    }

    return Column(
      children: [
        _buildChannelTitle(
          channel,
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(
              channelId,
            ),
            stream: messageStream,
            builder: (
              context,
              snapshot,
            ) {
              if (snapshot.connectionState ==
                      ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(
                      24,
                    ),
                    child: Text(
                      'Impossible de charger les messages.\n'
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final List<Map<String, dynamic>> messages =
                  snapshot.data ??
                      <Map<String, dynamic>>[];

              if (messages.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(
                      30,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🍺',
                          style: TextStyle(
                            fontSize: 46,
                          ),
                        ),
                        SizedBox(
                          height: 12,
                        ),
                        Text(
                          'Le Comptoir est encore silencieux...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(
                              0xffffd27a,
                            ),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(
                          height: 5,
                        ),
                        Text(
                          'Sois le premier aventurier à parler.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback(
                (_) {
                  _scrollToBottom();
                },
              );

              return ListView.separated(
                controller:
                    _messageScrollController,
                padding: const EdgeInsets.fromLTRB(
                  14,
                  14,
                  14,
                  20,
                ),
                itemCount: messages.length,
                separatorBuilder: (
                  context,
                  index,
                ) {
                  return const SizedBox(
                    height: 9,
                  );
                },
                itemBuilder: (
                  context,
                  index,
                ) {
                  return _buildMessage(
                    messages[index],
                  );
                },
              );
            },
          ),
        ),
        _buildMessageComposer(),
      ],
    );
  }

  Widget _buildChannelTitle(
    Map<String, dynamic> channel,
  ) {
    final String icon =
        channel['icon']?.toString() ?? '';

    final String name =
        channel['name']?.toString() ?? '';

    final String description =
        channel['description']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xff21150c,
        ),
        border: Border(
          bottom: BorderSide(
            color: Color(
              0xff4b301c,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            icon,
            style: const TextStyle(
              fontSize: 27,
            ),
          ),
          const SizedBox(
            width: 11,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(
                      0xffffd27a,
                    ),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(
    Map<String, dynamic> message,
  ) {
    final String authorId =
        message['author_id']?.toString() ?? '';

    final Map<String, dynamic>? profile =
        _asStringDynamicMap(
      message['author_profile'],
    );

    final String displayName =
        profile?['display_name']
                ?.toString()
                .trim() ??
            '';

    final String authorName =
        displayName.isNotEmpty
            ? displayName
            : _fallbackAuthorName(
                authorId,
              );

    final String content =
        message['content']?.toString() ?? '';

    final String createdAt =
        _formatMessageTime(
      message['created_at']?.toString(),
    );

    return Container(
      padding: const EdgeInsets.all(
        12,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xff24170e,
        ),
        borderRadius: BorderRadius.circular(
          13,
        ),
        border: Border.all(
          color: const Color(
            0xff4f331f,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _openPlayerCard(
                authorId: authorId,
                profile: profile,
              );
            },
            child: _buildAuthorAvatar(
              profile: profile,
              authorId: authorId,
              displayName: authorName,
            ),
          ),
          const SizedBox(
            width: 11,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _openPlayerCard(
                            authorId: authorId,
                            profile: profile,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                          ),
                          child: Text(
                            authorName,
                            overflow:
                                TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(
                                0xffffc857,
                              ),
                              fontWeight:
                                  FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Text(
                      createdAt,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 7,
                ),
                Text(
                  content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorAvatar({
    required Map<String, dynamic>? profile,
    required String authorId,
    required String displayName,
    double size = 48,
  }) {
    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    if (avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(
          12,
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
      authorId,
    );

    if (avatar == null) {
      return _buildAvatarFallback(
        displayName,
        size: size,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        12,
      ),
      child: SizedBox(
        width: 48,
        height: 48,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: 48,
          maxWidth: 48,
          minHeight: 72,
          maxHeight: 72,
          child: AvatarRenderer(
            avatar: avatar,
            size: 48,
            showFrame: false,
            compactHeadCrop: true,
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(
    String displayName, {
    double size = 48,
  }) {
    final String initial =
        displayName.trim().isNotEmpty
            ? displayName
                .trim()
                .substring(
                  0,
                  1,
                )
                .toUpperCase()
            : '?';

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(
          0xff5b3a20,
        ),
        borderRadius: BorderRadius.circular(
          12,
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
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ===========================================================================
  // MINI-PROFIL D'UN AVENTURIER
  // ===========================================================================

  Future<void> _openPlayerCard({
    required String authorId,
    required Map<String, dynamic>? profile,
  }) async {
    if (authorId.trim().isEmpty) {
      return;
    }

    Map<String, dynamic>? resolvedProfile = profile;

    if (resolvedProfile == null ||
        resolvedProfile['public_profile_data'] == null) {
      resolvedProfile =
          await TavernService.getPublicProfile(
        authorId,
      );
    }

    if (!mounted) {
      return;
    }

    final String displayName =
        resolvedProfile?['display_name']
                ?.toString()
                .trim() ??
            '';

    final String authorName =
        displayName.isNotEmpty
            ? displayName
            : _fallbackAuthorName(
                authorId,
              );

    final Map<String, dynamic>? publicData =
        _asStringDynamicMap(
      resolvedProfile?['public_profile_data'],
    );

    final String description =
        publicData?['description']
                ?.toString()
                .trim() ??
            '';

    final List<String> games =
        _stringList(
      publicData?['games'],
    );

    final bool isCurrentUser =
        SupabaseService.currentUser?.id ==
            authorId;

    final FriendRelationshipState relationshipState =
        isCurrentUser
            ? FriendRelationshipState.self
            : await FriendService.getRelationshipState(
                authorId,
              );

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (
        BuildContext sheetContext,
      ) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(
              10,
            ),
            padding: const EdgeInsets.fromLTRB(
              20,
              12,
              20,
              22,
            ),
            decoration: BoxDecoration(
              color: const Color(
                0xff21150e,
              ),
              borderRadius: BorderRadius.circular(
                24,
              ),
              border: Border.all(
                color: const Color(
                  0xff6f4a29,
                ),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 18,
                  offset: Offset(
                    0,
                    8,
                  ),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(
                      999,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 18,
                ),

                _buildAuthorAvatar(
                  profile: resolvedProfile,
                  authorId: authorId,
                  displayName: authorName,
                  size: 92,
                ),

                const SizedBox(
                  height: 14,
                ),

                Text(
                  authorName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(
                      0xffffd27a,
                    ),
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                const Text(
                  'Niveau 1 • Aventurier',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),

                if (description.isNotEmpty) ...[
                  const SizedBox(
                    height: 14,
                  ),
                  Text(
                    description,
                    maxLines: 3,
                    overflow:
                        TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                ],

                if (games.isNotEmpty) ...[
                  const SizedBox(
                    height: 14,
                  ),
                  Wrap(
                    alignment:
                        WrapAlignment.center,
                    spacing: 7,
                    runSpacing: 7,
                    children: games
                        .take(
                          4,
                        )
                        .map(
                          (
                            String game,
                          ) {
                            return Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration:
                                  BoxDecoration(
                                color:
                                    const Color(
                                  0xff160e09,
                                ),
                                borderRadius:
                                    BorderRadius.circular(
                                  999,
                                ),
                                border:
                                    Border.all(
                                  color:
                                      Colors.white12,
                                ),
                              ),
                              child: Text(
                                game,
                                style:
                                    const TextStyle(
                                  color:
                                      Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        )
                        .toList(),
                  ),
                ],

                const SizedBox(
                  height: 20,
                ),

                if (!isCurrentUser)
                  Row(
                    children: [
                      Expanded(
                        child:
                            FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              sheetContext,
                            );

                            _showPrivateMessagePending(
                              authorName,
                            );
                          },
                          icon: const Icon(
                            Icons
                                .chat_bubble_outline,
                          ),
                          label: const Text(
                            'Message privé',
                          ),
                          style:
                              FilledButton.styleFrom(
                            backgroundColor:
                                const Color(
                              0xff8b572a,
                            ),
                            foregroundColor:
                                Colors.white,
                            padding:
                                const EdgeInsets.symmetric(
                              vertical: 13,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 9,
                      ),

                      Expanded(
                        child:
                            _buildFriendActionButton(
                          sheetContext:
                              sheetContext,
                          authorId:
                              authorId,
                          authorName:
                              authorName,
                          relationshipState:
                              relationshipState,
                        ),
                      ),
                    ],
                  ),

                if (!isCurrentUser)
                  const SizedBox(
                    height: 8,
                  ),

                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        sheetContext,
                      );

                      _showPublicProfileSummary(
                        authorName:
                            authorName,
                        publicData:
                            publicData,
                      );
                    },
                    icon: const Icon(
                      Icons
                          .account_circle_outlined,
                    ),
                    label: Text(
                      isCurrentUser
                          ? 'Voir mon profil public'
                          : 'Voir le profil public',
                    ),
                    style:
                        TextButton.styleFrom(
                      foregroundColor:
                          const Color(
                        0xffffd27a,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPrivateMessagePending(
    String displayName,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          'Messagerie privée avec '
          '$displayName : prochaine étape.',
        ),
      ),
    );
  }

  // ===========================================================================
  // ACTION AMI DU MINI-PROFIL
  // ===========================================================================

  Widget _buildFriendActionButton({
    required BuildContext sheetContext,
    required String authorId,
    required String authorName,
    required FriendRelationshipState relationshipState,
  }) {
    IconData icon =
        Icons.person_add_alt_1;

    String label =
        'Ajouter';

    VoidCallback? onPressed;

    switch (relationshipState) {
      case FriendRelationshipState.self:
        label = 'Mon profil';
        icon = Icons.person_outline;
        onPressed = null;
        break;

      case FriendRelationshipState.none:
        label = 'Ajouter';
        icon = Icons.person_add_alt_1;
        onPressed = () {
          Navigator.pop(
            sheetContext,
          );

          _sendFriendRequest(
            authorId: authorId,
            authorName: authorName,
          );
        };
        break;

      case FriendRelationshipState.outgoingPending:
        label = 'En attente';
        icon = Icons.hourglass_top_rounded;
        onPressed = null;
        break;

      case FriendRelationshipState.incomingPending:
        label = 'Demande reçue';
        icon = Icons.mark_email_unread_outlined;
        onPressed = () {
          Navigator.pop(
            sheetContext,
          );

          if (!mounted) {
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$authorName t’a déjà envoyé une demande d’ami.',
              ),
            ),
          );
        };
        break;

      case FriendRelationshipState.friends:
        label = 'Amis';
        icon = Icons.people_alt_outlined;
        onPressed = null;
        break;
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
      ),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            const Color(
          0xffffd27a,
        ),
        disabledForegroundColor:
            Colors.white38,
        side: BorderSide(
          color: onPressed == null
              ? Colors.white24
              : const Color(
                  0xff9b642e,
                ),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: 13,
        ),
      ),
    );
  }

  Future<void> _sendFriendRequest({
    required String authorId,
    required String authorName,
  }) async {
    final FriendRequestSendResult result =
        await FriendService.sendFriendRequest(
      authorId,
    );

    if (!mounted) {
      return;
    }

    String message;

    switch (result) {
      case FriendRequestSendResult.sent:
        message =
            'Demande d’ami envoyée à $authorName.';
        break;

      case FriendRequestSendResult.alreadyPending:
        message =
            'Ta demande d’ami à $authorName est déjà en attente.';
        break;

      case FriendRequestSendResult.incomingPending:
        message =
            '$authorName t’a déjà envoyé une demande d’ami.';
        break;

      case FriendRequestSendResult.alreadyFriends:
        message =
            '$authorName est déjà dans tes amis.';
        break;

      case FriendRequestSendResult.invalidUser:
        message =
            'Impossible d’envoyer cette demande d’ami.';
        break;

      case FriendRequestSendResult.error:
        message =
            'Une erreur est survenue pendant l’envoi de la demande.';
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );
  }

  Future<void> _showPublicProfileSummary({
    required String authorName,
    required Map<String, dynamic>? publicData,
  }) async {
    final String description =
        publicData?['description']
                ?.toString()
                .trim() ??
            'Aucune description.';

    final List<String> games =
        _stringList(
      publicData?['games'],
    );

    final List<String> platforms =
        _mapNameList(
      publicData?['platforms'],
    );

    final List<String> networks =
        _networkList(
      publicData?['networks'],
    );

    await showDialog<void>(
      context: context,
      builder: (
        BuildContext dialogContext,
      ) {
        return AlertDialog(
          backgroundColor: const Color(
            0xff21150e,
          ),
          title: Text(
            authorName,
            style: const TextStyle(
              color: Color(
                0xffffd27a,
              ),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),

                if (games.isNotEmpty) ...[
                  const SizedBox(
                    height: 16,
                  ),
                  const Text(
                    'Jeux',
                    style: TextStyle(
                      color: Color(
                        0xffffd27a,
                      ),
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    games.join(
                      ' • ',
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],

                if (platforms.isNotEmpty) ...[
                  const SizedBox(
                    height: 16,
                  ),
                  const Text(
                    'Plateformes',
                    style: TextStyle(
                      color: Color(
                        0xffffd27a,
                      ),
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    platforms.join(
                      ' • ',
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],

                if (networks.isNotEmpty) ...[
                  const SizedBox(
                    height: 16,
                  ),
                  const Text(
                    'Réseaux visibles',
                    style: TextStyle(
                      color: Color(
                        0xffffd27a,
                      ),
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    networks.join(
                      '\n',
                    ),
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'Fermer',
              ),
            ),
          ],
        );
      },
    );
  }

  List<String> _stringList(
    dynamic value,
  ) {
    if (value is! List) {
      return <String>[];
    }

    return value
        .map(
          (
            dynamic item,
          ) =>
              item.toString().trim(),
        )
        .where(
          (
            String item,
          ) =>
              item.isNotEmpty,
        )
        .toList();
  }

  List<String> _mapNameList(
    dynamic value,
  ) {
    if (value is! List) {
      return <String>[];
    }

    final List<String> result =
        <String>[];

    for (final dynamic item in value) {
      if (item is! Map) {
        continue;
      }

      final String name =
          item['nom']
                  ?.toString()
                  .trim() ??
              '';

      if (name.isNotEmpty) {
        result.add(
          name,
        );
      }
    }

    return result;
  }

  List<String> _networkList(
    dynamic value,
  ) {
    if (value is! List) {
      return <String>[];
    }

    final List<String> result =
        <String>[];

    for (final dynamic item in value) {
      if (item is! Map) {
        continue;
      }

      final String name =
          item['nom']
                  ?.toString()
                  .trim() ??
              '';

      final String username =
          item['pseudo']
                  ?.toString()
                  .trim() ??
              '';

      if (name.isEmpty) {
        continue;
      }

      result.add(
        username.isEmpty
            ? name
            : '$name : $username',
      );
    }

    return result;
  }

  AvatarModel? _avatarFromProfile(
    Map<String, dynamic>? profile,
    String authorId,
  ) {
    if (profile == null) {
      return null;
    }

    final Map<String, dynamic>? avatarData =
        _asStringDynamicMap(
      profile['avatar_data'],
    );

    if (avatarData == null) {
      return null;
    }

    final String creationMode =
        avatarData['creationMode']
                ?.toString()
                .trim() ??
            '';

    if (creationMode != 'manual') {
      return null;
    }

    final DateTime now =
        DateTime.now();

    try {
      return AvatarModel.fromJson(
        {
          'userId':
              authorId.isEmpty
                  ? 'tavern-user'
                  : authorId,
          'creationMode': 'manual',
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

  Map<String, dynamic>? _asStringDynamicMap(
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

  String _fallbackAuthorName(
    String authorId,
  ) {
    if (authorId.isEmpty) {
      return 'Aventurier';
    }

    final String shortAuthor =
        authorId.length >= 8
            ? authorId.substring(
                0,
                8,
              )
            : authorId;

    return 'Aventurier $shortAuthor';
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        12,
        10,
        10,
        12,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xff181009,
        ),
        border: Border(
          top: BorderSide(
            color: Color(
              0xff53361f,
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
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization:
                  TextCapitalization.sentences,
              decoration: InputDecoration(
                counterText: '',
                hintText:
                    'Parler au Comptoir...',
                hintStyle: const TextStyle(
                  color: Colors.white38,
                ),
                filled: true,
                fillColor: const Color(
                  0xff27190f,
                ),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
              onSubmitted: (_) {
                _sendMessage();
              },
            ),
          ),
          const SizedBox(
            width: 8,
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor:
                    const Color(
                  0xff9b642e,
                ),
                foregroundColor:
                    Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),
              ),
              onPressed: _sendingMessage
                  ? null
                  : _sendMessage,
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

  Widget _buildFutureChannel(
    Map<String, dynamic> channel,
  ) {
    final String icon =
        channel['icon']?.toString() ?? '';

    final String name =
        channel['name']?.toString() ?? '';

    final String description =
        channel['description']?.toString() ?? '';

    return Column(
      children: [
        _buildChannelTitle(
          channel,
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(
                28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    icon,
                    style: const TextStyle(
                      fontSize: 55,
                    ),
                  ),
                  const SizedBox(
                    height: 13,
                  ),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(
                        0xffffd27a,
                      ),
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                  const SizedBox(
                    height: 14,
                  ),
                  const Text(
                    'Cette partie de la Taverne ouvrira bientôt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatMessageTime(
    String? rawDate,
  ) {
    if (rawDate == null || rawDate.isEmpty) {
      return '';
    }

    final DateTime? parsed =
        DateTime.tryParse(
      rawDate,
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
