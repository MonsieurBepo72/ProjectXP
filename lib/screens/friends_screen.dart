import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../services/friend_alias_service.dart';
import '../services/friend_service.dart';
import 'private_chat_screen.dart';
import '../widgets/avatar_renderer.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
  });

  @override
  State<FriendsScreen> createState() =>
      _FriendsScreenState();
}

class _FriendsScreenState
    extends State<FriendsScreen> {
  bool _loading = true;

  String? _errorMessage;

  List<Map<String, dynamic>> _friends =
      <Map<String, dynamic>>[];

  Map<String, String> _aliases =
      <String, String>{};

  @override
  void initState() {
    super.initState();

    _loadFriends();
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  Future<void> _loadFriends() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final List<Map<String, dynamic>> friends =
          await FriendService.getFriends();

      final Map<String, String> aliases =
          await FriendAliasService.getAliases();

      if (!mounted) {
        return;
      }

      setState(() {
        _friends = friends;
        _aliases = aliases;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'Impossible de charger la liste d’amis.\n$error';
      });
    }
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
          0xffffc857,
        ),
        centerTitle: true,
        title: const Text(
          'MES AMIS',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(
            0xffffc857,
          ),
          onRefresh: _loadFriends,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 220,
          ),
          Center(
            child: CircularProgressIndicator(
              color: Color(
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
        padding: const EdgeInsets.all(
          24,
        ),
        children: [
          const SizedBox(
            height: 120,
          ),
          const Icon(
            Icons.error_outline,
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
          Center(
            child: FilledButton(
              onPressed: _loadFriends,
              child: const Text(
                'Réessayer',
              ),
            ),
          ),
        ],
      );
    }

    if (_friends.isEmpty) {
      return ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(
          30,
        ),
        children: const [
          SizedBox(
            height: 120,
          ),
          Icon(
            Icons.people_outline,
            size: 58,
            color: Color(
              0xffffc857,
            ),
          ),
          SizedBox(
            height: 16,
          ),
          Text(
            'Aucun ami pour le moment',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(
                0xffffd27a,
              ),
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(
            height: 7,
          ),
          Text(
            'Ajoute des aventuriers depuis la Taverne pour les retrouver ici.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        14,
        16,
        14,
        28,
      ),
      itemCount: _friends.length,
      separatorBuilder: (
        context,
        index,
      ) {
        return const SizedBox(
          height: 12,
        );
      },
      itemBuilder: (
        context,
        index,
      ) {
        return _buildFriendCard(
          _friends[index],
        );
      },
    );
  }

  // ===========================================================================
  // CARTE AMI
  // ===========================================================================

  Widget _buildFriendCard(
    Map<String, dynamic> friendship,
  ) {
    final String friendId =
        friendship['friend_id']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic>? profile =
        _asMap(
      friendship['friend_profile'],
    );

    final String displayName =
        profile?['display_name']
                ?.toString()
                .trim() ??
            '';

    final String publicName =
        displayName.isNotEmpty
            ? displayName
            : 'Aventurier';

    final String? alias =
        _aliases[friendId];

    final String name =
        FriendAliasService.resolveDisplayName(
      publicDisplayName:
          publicName,
      alias:
          alias,
    );

    final bool hasAlias =
        alias != null &&
            alias.trim().isNotEmpty;

    final Map<String, dynamic>? publicData =
        _asMap(
      profile?['public_profile_data'],
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

    return Container(
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xff21150e,
        ),
        borderRadius: BorderRadius.circular(
          17,
        ),
        border: Border.all(
          color: const Color(
            0xff5a3a22,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              _buildAvatar(
                profile: profile,
                userId: friendId,
                displayName: name,
              ),

              const SizedBox(
                width: 13,
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
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    if (hasAlias) ...[
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        '@$publicName',
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],

                    if (description.isNotEmpty) ...[
                      const SizedBox(
                        height: 5,
                      ),
                      Text(
                        description,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          height: 1.35,
                        ),
                      ),
                    ],

                    if (games.isNotEmpty) ...[
                      const SizedBox(
                        height: 9,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: games
                            .take(
                              3,
                            )
                            .map(
                              (
                                String game,
                              ) {
                                return Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
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
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),

              PopupMenuButton<String>(
                tooltip: 'Options',
                color: const Color(
                  0xff21150e,
                ),
                iconColor: Colors.white54,
                onSelected: (
                  String value,
                ) {
                  if (value ==
                      'alias') {
                    _editAlias(
                      friendId:
                          friendId,
                      publicDisplayName:
                          publicName,
                      currentAlias:
                          alias,
                    );
                  }

                  if (value ==
                      'remove_alias') {
                    _removeAlias(
                      friendId:
                          friendId,
                      publicDisplayName:
                          publicName,
                    );
                  }

                  if (value ==
                      'remove') {
                    _confirmRemoveFriend(
                      friendId:
                          friendId,
                      displayName:
                          name,
                    );
                  }
                },
                itemBuilder: (
                  context,
                ) {
                  return [
                    PopupMenuItem<String>(
                      value: 'alias',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            color: Color(
                              0xffffd27a,
                            ),
                          ),
                          const SizedBox(
                            width: 9,
                          ),
                          Text(
                            hasAlias
                                ? 'Modifier le surnom'
                                : 'Définir un surnom',
                          ),
                        ],
                      ),
                    ),

                    if (hasAlias)
                      const PopupMenuItem<String>(
                        value:
                            'remove_alias',
                        child: Row(
                          children: [
                            Icon(
                              Icons
                                  .restart_alt_rounded,
                              color:
                                  Colors.white70,
                            ),
                            SizedBox(
                              width: 9,
                            ),
                            Text(
                              'Retirer le surnom',
                            ),
                          ],
                        ),
                      ),

                    const PopupMenuDivider(),

                    const PopupMenuItem<String>(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(
                            Icons
                                .person_remove_outlined,
                            color:
                                Colors.redAccent,
                          ),
                          SizedBox(
                            width: 9,
                          ),
                          Text(
                            'Retirer des amis',
                          ),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),

          const SizedBox(
            height: 14,
          ),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: friendId.isEmpty
                      ? null
                      : () {
                          _openPrivateChat(
                            friendId:
                                friendId,
                            displayName:
                                name,
                            profile:
                                profile,
                          );
                        },
                  icon: const Icon(
                    Icons.chat_bubble_outline,
                  ),
                  label: const Text(
                    'Message',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(
                      0xff8b572a,
                    ),
                    foregroundColor:
                        Colors.white,
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                width: 9,
              ),

              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showPublicProfile(
                      displayName:
                          publicName,
                      publicData: publicData,
                    );
                  },
                  icon: const Icon(
                    Icons
                        .account_circle_outlined,
                  ),
                  label: const Text(
                    'Profil',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        const Color(
                      0xffffd27a,
                    ),
                    side: const BorderSide(
                      color: Color(
                        0xff9b642e,
                      ),
                    ),
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SURNOM PRIVÉ
  // ===========================================================================

  Future<void> _editAlias({
    required String friendId,
    required String publicDisplayName,
    required String? currentAlias,
  }) async {
    if (friendId.isEmpty) {
      return;
    }

    final TextEditingController controller =
        TextEditingController(
      text:
          currentAlias?.trim() ?? '',
    );

    final String? nickname =
        await showDialog<String>(
      context: context,
      builder: (
        BuildContext dialogContext,
      ) {
        return AlertDialog(
          backgroundColor: const Color(
            0xff21150e,
          ),
          title: Text(
            currentAlias == null ||
                    currentAlias.trim().isEmpty
                ? 'Définir un surnom'
                : 'Modifier le surnom',
            style: const TextStyle(
              color: Color(
                0xffffd27a,
              ),
            ),
          ),
          content: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Pseudo public : @$publicDisplayName',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),

              const SizedBox(
                height: 14,
              ),

              TextField(
                controller:
                    controller,
                autofocus: true,
                maxLength: 30,
                textCapitalization:
                    TextCapitalization.words,
                style: const TextStyle(
                  color: Colors.white,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Surnom',
                  labelStyle:
                      TextStyle(
                    color:
                        Colors.white54,
                  ),
                  hintText:
                      'Ex. Jojo',
                  hintStyle:
                      TextStyle(
                    color:
                        Colors.white30,
                  ),
                  enabledBorder:
                      OutlineInputBorder(
                    borderSide:
                        BorderSide(
                      color:
                          Colors.white24,
                    ),
                  ),
                  focusedBorder:
                      OutlineInputBorder(
                    borderSide:
                        BorderSide(
                      color:
                          Color(
                        0xffffc857,
                      ),
                    ),
                  ),
                ),
                onSubmitted: (
                  String value,
                ) {
                  final String clean =
                      value.trim();

                  if (clean.isNotEmpty) {
                    Navigator.pop(
                      dialogContext,
                      clean,
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'Annuler',
              ),
            ),
            FilledButton(
              onPressed: () {
                final String clean =
                    controller.text.trim();

                if (clean.isEmpty) {
                  return;
                }

                Navigator.pop(
                  dialogContext,
                  clean,
                );
              },
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xff8b572a,
                ),
              ),
              child: const Text(
                'Enregistrer',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (nickname == null ||
        nickname.trim().isEmpty) {
      return;
    }

    final bool saved =
        await FriendAliasService.setAlias(
      friendId: friendId,
      nickname: nickname,
    );

    if (!mounted) {
      return;
    }

    if (saved) {
      setState(() {
        _aliases[friendId] =
            nickname.trim();
      });
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Surnom enregistré : ${nickname.trim()}'
              : 'Impossible d’enregistrer ce surnom.',
        ),
      ),
    );
  }

  Future<void> _removeAlias({
    required String friendId,
    required String publicDisplayName,
  }) async {
    if (friendId.isEmpty) {
      return;
    }

    final bool removed =
        await FriendAliasService.removeAlias(
      friendId,
    );

    if (!mounted) {
      return;
    }

    if (removed) {
      setState(() {
        _aliases.remove(
          friendId,
        );
      });
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? 'Le pseudo @$publicDisplayName est de nouveau affiché.'
              : 'Impossible de retirer ce surnom.',
        ),
      ),
    );
  }

  // ===========================================================================
  // MESSAGE PRIVÉ
  // ===========================================================================

  Future<void> _openPrivateChat({
    required String friendId,
    required String displayName,
    required Map<String, dynamic>? profile,
  }) async {
    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic>? avatarData =
        _asMap(
      profile?['avatar_data'],
    );

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (
          BuildContext context,
        ) {
          return PrivateChatScreen(
            friendId: friendId,
            displayName: displayName,
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
  }

  // ===========================================================================
  // PROFIL PUBLIC
  // ===========================================================================

  Future<void> _showPublicProfile({
    required String displayName,
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
            displayName,
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

  // ===========================================================================
  // RETIRER UN AMI
  // ===========================================================================

  Future<void> _confirmRemoveFriend({
    required String friendId,
    required String displayName,
  }) async {
    if (friendId.isEmpty) {
      return;
    }

    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        BuildContext dialogContext,
      ) {
        return AlertDialog(
          backgroundColor: const Color(
            0xff21150e,
          ),
          title: const Text(
            'Retirer cet ami ?',
            style: TextStyle(
              color: Color(
                0xffffd27a,
              ),
            ),
          ),
          content: Text(
            '$displayName sera retiré de ta liste d’amis.',
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Annuler',
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Retirer',
                style: TextStyle(
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final bool removed =
        await FriendService.removeFriend(
      friendId,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? '$displayName a été retiré de tes amis.'
              : 'Impossible de retirer cet ami.',
        ),
      ),
    );

    if (removed) {
      await FriendAliasService.removeAlias(
        friendId,
      );

      await _loadFriends();
    }
  }

  // ===========================================================================
  // AVATAR
  // ===========================================================================

  Widget _buildAvatar({
    required Map<String, dynamic>? profile,
    required String userId,
    required String displayName,
  }) {
    const double size = 66;

    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    if (avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(
          15,
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
      userId,
    );

    if (avatar == null) {
      return _buildAvatarFallback(
        displayName,
        size: size,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        15,
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
    String displayName, {
    required double size,
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
          15,
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
          fontSize: 25,
          fontWeight: FontWeight.bold,
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
              userId.isEmpty
                  ? 'friend-user'
                  : userId,
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

  // ===========================================================================
  // OUTILS
  // ===========================================================================

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
}
