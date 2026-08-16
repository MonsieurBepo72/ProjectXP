import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../models/squad_join_request.dart';
import '../services/auth_service.dart';
import '../services/avatar_storage.dart';
import '../services/squad_request_storage.dart';
import '../widgets/avatar_renderer.dart';
import 'public_profile_screen.dart';

class SquadPhoneScreen
    extends StatefulWidget {
  const SquadPhoneScreen({
    super.key,
  });

  @override
  State<SquadPhoneScreen> createState() =>
      _SquadPhoneScreenState();
}

class _SquadPhoneScreenState
    extends State<SquadPhoneScreen> {
  String _currentUserId = '';

  List<SquadJoinRequest> _incoming =
      <SquadJoinRequest>[];

  List<SquadJoinRequest> _outgoing =
      <SquadJoinRequest>[];

  Map<String, String> _resolvedNames =
      <String, String>{};

  Map<String, AvatarModel?> _requesterAvatars =
      <String, AvatarModel?>{};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? userId =
        await AuthService.getCurrentUserId();

    final String id =
        userId?.trim() ?? '';

    if (id.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _currentUserId = '';
        _incoming =
            <SquadJoinRequest>[];
        _outgoing =
            <SquadJoinRequest>[];
        _resolvedNames =
            <String, String>{};
        _requesterAvatars =
            <String, AvatarModel?>{};
        _loading = false;
      });

      return;
    }

    final List<SquadJoinRequest> incoming =
        await SquadRequestStorage
            .incomingForUser(id);

    final List<SquadJoinRequest> outgoing =
        await SquadRequestStorage
            .outgoingForUser(id);

    final Map<String, String> resolvedNames =
        <String, String>{};

    final Set<String> requesterIds = {
      ...incoming.map(
        (request) =>
            request.requesterId,
      ),
      ...outgoing.map(
        (request) =>
            request.requesterId,
      ),
    };

    final Map<String, AvatarModel?>
        requesterAvatars =
        <String, AvatarModel?>{};

    for (final String requesterId
        in requesterIds) {
      final String? username =
          await AuthService
              .getUsernameForUserId(
        requesterId,
      );

      if (username != null &&
          username.trim().isNotEmpty) {
        resolvedNames[requesterId] =
            username.trim();
      }

      requesterAvatars[requesterId] =
          await AvatarStorage.loadAvatar(
        requesterId,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUserId = id;
      _incoming = incoming;
      _outgoing = outgoing;
      _resolvedNames =
          resolvedNames;
      _requesterAvatars =
          requesterAvatars;
      _loading = false;
    });
  }

  String _displayName(
    SquadJoinRequest request,
  ) {
    final String resolved =
        _resolvedNames[
                request.requesterId]
            ?.trim() ??
            '';

    if (resolved.isNotEmpty) {
      return resolved;
    }

    final String stored =
        request.requesterName.trim();

    return stored.isEmpty
        ? 'Joueur'
        : stored;
  }

  Future<void> _openRequesterProfile(
    SquadJoinRequest request,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) =>
            PublicProfileScreen(
          userId:
              request.requesterId,
        ),
      ),
    );
  }

  Future<void> _accept(
    SquadJoinRequest request,
  ) async {
    final bool? confirmed =
        await _confirm(
      title:
          'Accepter la demande',
      message:
          'Ajouter ${_displayName(request)} à ${request.teamName} ?',
      actionLabel:
          'ACCEPTER',
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await SquadRequestStorage
            .acceptRequest(
      requestId: request.id,
      handlerUserId:
          _currentUserId,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible d’accepter cette demande.',
      );
      return;
    }

    _showMessage(
      '${_displayName(request)} a rejoint ${request.teamName}.',
    );

    await _load();
  }

  Future<void> _reject(
    SquadJoinRequest request,
  ) async {
    final bool? confirmed =
        await _confirm(
      title:
          'Refuser la demande',
      message:
          'Refuser la demande de ${_displayName(request)} ?',
      actionLabel:
          'REFUSER',
      destructive: true,
    );

    if (confirmed != true) {
      return;
    }

    final bool success =
        await SquadRequestStorage
            .rejectRequest(
      requestId: request.id,
      handlerUserId:
          _currentUserId,
    );

    if (!mounted) {
      return;
    }

    if (!success) {
      _showMessage(
        'Impossible de refuser cette demande.',
      );
      return;
    }

    await _load();
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String actionLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              const Color(0xff2b1a12),
          title: Text(
            title,
            style:
                const TextStyle(
              color:
                  Color(
                0xffffc857,
              ),
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          content: Text(
            message,
            style:
                const TextStyle(
              color:
                  Colors.white70,
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
              child:
                  const Text(
                'ANNULER',
                style:
                    TextStyle(
                  color:
                      Colors.white54,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child:
                  Text(
                actionLabel,
                style:
                    TextStyle(
                  color: destructive
                      ? Colors.redAccent
                      : const Color(
                          0xffffc857,
                        ),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor:
            const Color(0xff21150e),
        foregroundColor:
            const Color(0xffffc857),
        centerTitle: true,
        title: const Text(
          'COMMUNICATEUR XP',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
            letterSpacing:
                1.2,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(
                  color:
                      Color(
                    0xffffc857,
                  ),
                ),
              )
            : RefreshIndicator(
                color:
                    const Color(
                  0xffffc857,
                ),
                onRefresh:
                    _load,
                child:
                    ListView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  padding:
                      const EdgeInsets.fromLTRB(
                    18,
                    20,
                    18,
                    30,
                  ),
                  children: [
                    const _PhoneHeader(),

                    const SizedBox(
                      height: 24,
                    ),

                    const _SectionTitle(
                      icon:
                          Icons.group_add,
                      title:
                          'DEMANDES REÇUES',
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    if (_incoming
                        .isEmpty)
                      const _EmptyInbox(
                        message:
                            'Aucune demande reçue.',
                      )
                    else
                      ..._incoming.map(
                        (request) =>
                            _IncomingRequestCard(
                          request:
                              request,
                          displayName:
                              _displayName(
                            request,
                          ),
                          avatar:
                              _requesterAvatars[
                            request.requesterId
                          ],
                          onOpenProfile:
                              () {
                            _openRequesterProfile(
                              request,
                            );
                          },
                          onAccept:
                              request.isPending
                                  ? () {
                                      _accept(
                                        request,
                                      );
                                    }
                                  : null,
                          onReject:
                              request.isPending
                                  ? () {
                                      _reject(
                                        request,
                                      );
                                    }
                                  : null,
                        ),
                      ),

                    const SizedBox(
                      height: 26,
                    ),

                    const _SectionTitle(
                      icon:
                          Icons.outbox_outlined,
                      title:
                          'MES DEMANDES',
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    if (_outgoing
                        .isEmpty)
                      const _EmptyInbox(
                        message:
                            'Tu n’as envoyé aucune demande.',
                      )
                    else
                      ..._outgoing.map(
                        (request) =>
                            _OutgoingRequestCard(
                          request:
                              request,
                        ),
                      ),

                    const SizedBox(
                      height: 24,
                    ),

                    const Text(
                      'Les futures invitations de joueurs et messages seront centralisés ici également.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.white30,
                        fontSize:
                            11,
                        height:
                            1.4,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// =============================================================================
// WIDGETS
// =============================================================================

class _PhoneHeader
    extends StatelessWidget {
  const _PhoneHeader();

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff21150e,
        ),
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        border:
            Border.all(
          color:
              const Color(
            0xffffc857,
          ),
          width:
              1.5,
        ),
      ),
      child:
          const Row(
        children: [
          Icon(
            Icons.smartphone,
            color:
                Color(
              0xffffc857,
            ),
            size:
                34,
          ),
          SizedBox(
            width:
                14,
          ),
          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'TÉLÉPHONE DU HALL',
                  style:
                      TextStyle(
                    color:
                        Color(
                      0xffffc857,
                    ),
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                SizedBox(
                  height:
                      4,
                ),
                Text(
                  'Invitations, demandes et alertes de Project XP.',
                  style:
                      TextStyle(
                    color:
                        Colors.white54,
                    fontSize:
                        12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle
    extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          color:
              const Color(
            0xffffc857,
          ),
          size:
              20,
        ),
        const SizedBox(
          width:
              8,
        ),
        Text(
          title,
          style:
              const TextStyle(
            color:
                Color(
              0xffffc857,
            ),
            fontSize:
                15,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _IncomingRequestCard
    extends StatelessWidget {
  final SquadJoinRequest request;
  final String displayName;
  final AvatarModel? avatar;
  final VoidCallback onOpenProfile;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _IncomingRequestCard({
    required this.request,
    required this.displayName,
    required this.avatar,
    required this.onOpenProfile,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom:
            10,
      ),
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff21150e,
        ),
        borderRadius:
            BorderRadius.circular(
          15,
        ),
        border:
            Border.all(
          color: request.isPending
              ? const Color(
                  0xffffc857,
                )
              : Colors.white12,
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenProfile,
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 3,
                ),
                child: Row(
                  children: [
                    _RequesterAvatar(
                      avatar: avatar,
                    ),
                    const SizedBox(
                      width:
                          11,
                    ),
                    Expanded(
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height:
                                3,
                          ),
                          Text(
                            'souhaite rejoindre ${request.teamName}',
                            style:
                                const TextStyle(
                              color:
                                  Colors.white60,
                              fontSize:
                                  12,
                            ),
                          ),
                          const SizedBox(
                            height:
                                3,
                          ),
                          const Text(
                            'Appuie pour voir le profil',
                            style:
                                TextStyle(
                              color:
                                  Color(
                                0xffffc857,
                              ),
                              fontSize:
                                  10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width:
                          8,
                    ),
                    _StatusChip(
                      request:
                          request,
                    ),
                    const SizedBox(
                      width:
                          4,
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color:
                          Colors.white38,
                      size:
                          20,
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (request.isPending) ...[
            const SizedBox(
              height:
                  13,
            ),
            Row(
              children: [
                Expanded(
                  child:
                      OutlinedButton(
                    onPressed:
                        onReject,
                    style:
                        OutlinedButton.styleFrom(
                      foregroundColor:
                          Colors.redAccent,
                      side:
                          const BorderSide(
                        color:
                            Colors.redAccent,
                      ),
                    ),
                    child:
                        const Text(
                      'REFUSER',
                    ),
                  ),
                ),
                const SizedBox(
                  width:
                      10,
                ),
                Expanded(
                  child:
                      ElevatedButton(
                    onPressed:
                        onAccept,
                    style:
                        ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(
                        0xffffc857,
                      ),
                      foregroundColor:
                          Colors.black,
                    ),
                    child:
                        const Text(
                      'ACCEPTER',
                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RequesterAvatar
    extends StatelessWidget {
  final AvatarModel? avatar;

  const _RequesterAvatar({
    required this.avatar,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final AvatarModel? value =
        avatar;

    return Container(
      width: 48,
      height: 58,
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff160e09,
        ),
        borderRadius:
            BorderRadius.circular(
          11,
        ),
        border:
            Border.all(
          color:
              const Color(
            0xffffc857,
          ),
        ),
      ),
      clipBehavior:
          Clip.antiAlias,
      alignment:
          Alignment.center,
      child: value == null
          ? const Icon(
              Icons.person,
              color:
                  Color(
                0xffffc857,
              ),
              size: 28,
            )
          : FittedBox(
              fit:
                  BoxFit.contain,
              child:
                  AvatarRenderer(
                avatar: value,
                size: 44,
                showFrame: false,
                compactHeadCrop: true,
              ),
            ),
    );
  }
}

class _OutgoingRequestCard
    extends StatelessWidget {
  final SquadJoinRequest request;

  const _OutgoingRequestCard({
    required this.request,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom:
            10,
      ),
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff21150e,
        ),
        borderRadius:
            BorderRadius.circular(
          15,
        ),
        border:
            Border.all(
          color:
              Colors.white12,
        ),
      ),
      child:
          Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            color:
                Color(
              0xffffc857,
            ),
            size:
                30,
          ),
          const SizedBox(
            width:
                12,
          ),
          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  request.teamName,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height:
                      3,
                ),
                Text(
                  _statusText(
                    request,
                  ),
                  style:
                      const TextStyle(
                    color:
                        Colors.white54,
                    fontSize:
                        12,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(
            request:
                request,
          ),
        ],
      ),
    );
  }

  String _statusText(
    SquadJoinRequest request,
  ) {
    if (request.isAccepted) {
      return 'Ta demande a été acceptée.';
    }

    if (request.isRejected) {
      return 'Ta demande a été refusée.';
    }

    return 'En attente de réponse.';
  }
}

class _StatusChip
    extends StatelessWidget {
  final SquadJoinRequest request;

  const _StatusChip({
    required this.request,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final String text;
    final IconData icon;

    if (request.isAccepted) {
      text = 'ACCEPTÉE';
      icon =
          Icons.check_circle;
    } else if (request.isRejected) {
      text = 'REFUSÉE';
      icon =
          Icons.cancel;
    } else {
      text = 'EN ATTENTE';
      icon =
          Icons.schedule;
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal:
            8,
        vertical:
            5,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff3a271c,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                const Color(
              0xffffc857,
            ),
            size:
                13,
          ),
          const SizedBox(
            width:
                4,
          ),
          Text(
            text,
            style:
                const TextStyle(
              color:
                  Color(
                0xffffc857,
              ),
              fontSize:
                  8,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInbox
    extends StatelessWidget {
  final String message;

  const _EmptyInbox({
    required this.message,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xff21150e,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border:
            Border.all(
          color:
              Colors.white12,
        ),
      ),
      child:
          Text(
        message,
        textAlign:
            TextAlign.center,
        style:
            const TextStyle(
          color:
              Colors.white38,
          fontSize:
              12,
        ),
      ),
    );
  }
}
