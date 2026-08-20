import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../services/friend_service.dart';
import '../widgets/avatar_renderer.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({
    super.key,
  });

  @override
  State<FriendRequestsScreen> createState() =>
      _FriendRequestsScreenState();
}

class _FriendRequestsScreenState
    extends State<FriendRequestsScreen> {
  bool _loading = true;

  String? _errorMessage;

  List<Map<String, dynamic>> _requests =
      <Map<String, dynamic>>[];

  final Set<String> _processingRequestIds =
      <String>{};

  @override
  void initState() {
    super.initState();

    _loadRequests();
  }

  // ===========================================================================
  // CHARGEMENT
  // ===========================================================================

  Future<void> _loadRequests() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final List<Map<String, dynamic>> requests =
          await FriendService.getIncomingRequests();

      if (!mounted) {
        return;
      }

      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage =
            'Impossible de charger les demandes d’ami.\n$error';
      });
    }
  }

  // ===========================================================================
  // ACCEPTER / REFUSER
  // ===========================================================================

  Future<void> _respondToRequest({
    required Map<String, dynamic> request,
    required bool accept,
  }) async {
    final String requestId =
        request['id']?.toString().trim() ?? '';

    if (requestId.isEmpty ||
        _processingRequestIds.contains(
          requestId,
        )) {
      return;
    }

    setState(() {
      _processingRequestIds.add(
        requestId,
      );
    });

    final FriendRequestResponseResult result =
        await FriendService.respondToFriendRequest(
      requestId: requestId,
      accept: accept,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _processingRequestIds.remove(
        requestId,
      );
    });

    String message;

    switch (result) {
      case FriendRequestResponseResult.accepted:
        message =
            'Demande acceptée. Vous êtes maintenant amis.';
        break;

      case FriendRequestResponseResult.declined:
        message =
            'Demande refusée.';
        break;

      case FriendRequestResponseResult.error:
        message =
            'Impossible de traiter cette demande.';
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );

    if (result !=
        FriendRequestResponseResult.error) {
      await _loadRequests();
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
          'DEMANDES D’AMI',
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
          onRefresh: _loadRequests,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics:
            AlwaysScrollableScrollPhysics(),
        children: [
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
              onPressed: _loadRequests,
              child: const Text(
                'Réessayer',
              ),
            ),
          ),
        ],
      );
    }

    if (_requests.isEmpty) {
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
            'Aucune demande d’ami',
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
            'Les demandes reçues dans la Taverne apparaîtront ici.',
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
      itemCount: _requests.length,
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
        return _buildRequestCard(
          _requests[index],
        );
      },
    );
  }

  // ===========================================================================
  // CARTE DE DEMANDE
  // ===========================================================================

  Widget _buildRequestCard(
    Map<String, dynamic> request,
  ) {
    final String requestId =
        request['id']?.toString().trim() ?? '';

    final String senderId =
        request['sender_id']
                ?.toString()
                .trim() ??
            '';

    final Map<String, dynamic>? profile =
        _asMap(
      request['sender_profile'],
    );

    final String displayName =
        profile?['display_name']
                ?.toString()
                .trim() ??
            '';

    final String name =
        displayName.isNotEmpty
            ? displayName
            : 'Aventurier';

    final Map<String, dynamic>? publicData =
        _asMap(
      profile?['public_profile_data'],
    );

    final String description =
        publicData?['description']
                ?.toString()
                .trim() ??
            '';

    final bool processing =
        _processingRequestIds.contains(
      requestId,
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
                userId: senderId,
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
                    const SizedBox(
                      height: 3,
                    ),
                    const Text(
                      'souhaite devenir ton ami',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(
                        height: 8,
                      ),
                      Text(
                        description,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
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
                  onPressed: processing
                      ? null
                      : () {
                          _respondToRequest(
                            request: request,
                            accept: true,
                          );
                        },
                  icon: processing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.check_rounded,
                        ),
                  label: const Text(
                    'Accepter',
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
                  onPressed: processing
                      ? null
                      : () {
                          _respondToRequest(
                            request: request,
                            accept: false,
                          );
                        },
                  icon: const Icon(
                    Icons.close_rounded,
                  ),
                  label: const Text(
                    'Refuser',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        Colors.white70,
                    side: const BorderSide(
                      color: Colors.white24,
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
  // AVATAR
  // ===========================================================================

  Widget _buildAvatar({
    required Map<String, dynamic>? profile,
    required String userId,
    required String displayName,
  }) {
    const double size = 62;

    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    if (avatarUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(
          14,
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
        14,
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
          14,
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
          fontSize: 24,
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
                  ? 'friend-request-user'
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
