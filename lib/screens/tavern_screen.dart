import 'dart:async';

import 'package:flutter/material.dart';

import '../models/avatar_model.dart';
import '../services/content_moderation_service.dart';
import '../services/friend_service.dart';
import '../services/online_presence_service.dart';
import '../services/project_xp_admin_service.dart';
import '../services/project_xp_message_send_result.dart';
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

  // ===========================================================================
  // TAVERNE V5 — DÉCOR FIDÈLE + RESPONSIVE
  // ===========================================================================
  //
  // Le décor est découpé en assets indépendants afin de garder la composition
  // de la maquette tout en laissant les messages, avatars et contrôles 100 %
  // interactifs. Chaque zone se redimensionne indépendamment pour éviter les
  // débordements sur les petits téléphones et les écrans très larges.

  static const String _tavernHeaderAsset =
      'assets/images/tavern/tavern_header.png';

  static const String _tavernTabPanelAsset =
      'assets/images/tavern/tavern_tab_panel.png';

  static const String _tavernShelfLeftAsset =
      'assets/images/tavern/tavern_shelf_left.jpg';

  static const String _tavernShelfRightAsset =
      'assets/images/tavern/tavern_shelf_right.jpg';

  static const String _tavernWallAsset =
      'assets/images/tavern/tavern_wall.jpg';

  static const String _tavernWoodStripAsset =
      'assets/images/tavern/tavern_wood_strip.jpg';

  static const Color _tavernBackground =
      Color(0xff0d0806);

  static const Color _tavernPanel =
      Color(0xff17100c);

  static const Color _tavernGold =
      Color(0xffffca63);

  static const Color _tavernGoldDeep =
      Color(0xff9e642b);

  static const Color _tavernPurple =
      Color(0xffb15cff);

  static const double _maxTavernWidth =
      760;

  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _messageScrollController =
      ScrollController();

  bool _loadingChannels = true;
  bool _sendingMessage = false;
  bool _isProjectXpAdmin = false;
  bool _resettingTavern = false;

  bool _didPrecacheTavernAssets = false;
  int _lastAutoScrollItemCount = -1;

  String? _pendingMessageContent;
  String? _pendingMessageChannelId;
  DateTime? _pendingMessageCreatedAt;

  String? _errorMessage;

  List<Map<String, dynamic>> _channels =
      <Map<String, dynamic>>[];

  Map<String, dynamic>? _selectedChannel;

  Stream<List<Map<String, dynamic>>>? _messageStream;

  @override
  void initState() {
    super.initState();

    _loadChannels();
    _loadAdminAccess();

    unawaited(
      ContentModerationService.warmUp(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didPrecacheTavernAssets) {
      return;
    }

    _didPrecacheTavernAssets = true;

    // Le premier frame reste léger. Ensuite, on prépare le décor dans le
    // cache d'images pour éviter un pic de décodage au moment d'ouvrir la
    // Taverne, particulièrement visible sur les anciens Android.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!mounted) {
          return;
        }

        const List<String> assets =
            <String>[
          _tavernHeaderAsset,
          _tavernTabPanelAsset,
          _tavernShelfLeftAsset,
          _tavernShelfRightAsset,
          _tavernWallAsset,
          _tavernWoodStripAsset,
        ];

        for (final String asset in assets) {
          unawaited(
            precacheImage(
              AssetImage(asset),
              context,
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // ADMIN PROJECT XP
  // ===========================================================================

  Future<void> _loadAdminAccess() async {
    final bool isAdmin =
        await ProjectXpAdminService.isCurrentUserAdmin();

    if (!mounted) {
      return;
    }

    setState(() {
      _isProjectXpAdmin = isAdmin;
    });
  }

  Future<void> _confirmResetTavern() async {
    if (!_isProjectXpAdmin ||
        _resettingTavern) {
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
            'Réinitialiser la Taverne ?',
            style: TextStyle(
              color: Color(
                0xffffd27a,
              ),
            ),
          ),
          content: const Text(
            'Tous les messages publics de la Taverne seront supprimés.\n\n'
            'Les channels, profils, amis et messages privés seront conservés.',
            style: TextStyle(
              color: Colors.white70,
              height: 1.4,
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
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor:
                    Colors.redAccent,
                foregroundColor:
                    Colors.white,
              ),
              icon: const Icon(
                Icons.delete_sweep_rounded,
              ),
              label: const Text(
                'Réinitialiser',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true ||
        !mounted) {
      return;
    }

    setState(() {
      _resettingTavern = true;
    });

    final int? deletedCount =
        await ProjectXpAdminService
            .resetTavernMessages();

    if (!mounted) {
      return;
    }

    setState(() {
      _resettingTavern = false;
    });

    if (deletedCount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Réinitialisation impossible. Vérifie les droits administrateur.',
          ),
        ),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deletedCount == 1
              ? 'Taverne réinitialisée : 1 message supprimé.'
              : 'Taverne réinitialisée : $deletedCount messages supprimés.',
        ),
      ),
    );
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
      _lastAutoScrollItemCount = -1;
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

    final ContentModerationResult moderation =
        ContentModerationService.checkTextImmediate(
      content,
    );

    if (moderation.blocked) {
      // Un message refusé par la modération ne doit pas rester dans
      // la zone de saisie : on repart immédiatement sur un champ propre.
      _messageController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce message contient un contenu interdit par les règles de Project XP.',
          ),
        ),
      );

      return;
    }

    // Affichage optimiste : le joueur voit immédiatement son message.
    // Il n'est cependant PAS encore publié aux autres joueurs : seule l'Edge
    // Function peut l'insérer après la modération serveur.
    setState(() {
      _sendingMessage = true;
      _pendingMessageContent = content;
      _pendingMessageChannelId = channelId;
      _pendingMessageCreatedAt = DateTime.now();
      _messageController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        _scrollToBottom();
      },
    );

    final ProjectXpMessageSendResult result =
        await TavernService.sendMessage(
      channelId: channelId,
      content: content,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _sendingMessage = false;
      _pendingMessageContent = null;
      _pendingMessageChannelId = null;
      _pendingMessageCreatedAt = null;
    });

    if (result.sent) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          _scrollToBottom();
        },
      );

      return;
    }

    if (result.blocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce message a été bloqué par la modération de Project XP.',
          ),
        ),
      );

      return;
    }

    // Une panne réseau ne doit pas faire perdre le texte du joueur.
    if (_messageController.text.trim().isEmpty) {
      _messageController.text = content;
      _messageController.selection =
          TextSelection.collapsed(
        offset: content.length,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Impossible d’envoyer le message pour le moment.',
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

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: _tavernBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
            BuildContext context,
            BoxConstraints constraints,
          ) {
            final double width =
                constraints.maxWidth
                    .clamp(
                      0.0,
                      _maxTavernWidth,
                    )
                    .toDouble();

            return Center(
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
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
          },
        ),
      ),
    );
  }


  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final double screenHeight =
            MediaQuery.sizeOf(
          context,
        ).height;

        final bool landscape =
            MediaQuery.orientationOf(
                  context,
                ) ==
                Orientation.landscape;

        final double naturalHeight =
            width *
            (220 / 924);

        final double maxHeight =
            landscape
                ? 92
                : screenHeight < 620
                    ? 86
                    : 132;

        final double height =
            naturalHeight
                .clamp(
                  78.0,
                  maxHeight,
                )
                .toDouble();

        final double edgeButtonSize =
            (height * 0.48)
                .clamp(
                  36.0,
                  46.0,
                )
                .toDouble();

        final double phoneSlotWidth =
            (edgeButtonSize + 8)
                .clamp(
                  44.0,
                  56.0,
                )
                .toDouble();

        final double presenceHeight =
            (edgeButtonSize * 0.82)
                .clamp(
                  34.0,
                  40.0,
                )
                .toDouble();

        final double dpr =
            MediaQuery.devicePixelRatioOf(
          context,
        );

        final int headerCacheWidth =
            (width * dpr)
                .round()
                .clamp(
                  320,
                  924,
                )
                .toInt();

        return SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _tavernHeaderAsset,
                fit: BoxFit.fill,
                alignment:
                    Alignment.center,
                cacheWidth:
                    headerCacheWidth,
                filterQuality:
                    FilterQuality.medium,
                gaplessPlayback: true,
              ),
              const DecoratedBox(
                decoration:
                    BoxDecoration(
                  gradient:
                      LinearGradient(
                    begin:
                        Alignment.topCenter,
                    end:
                        Alignment.bottomCenter,
                    colors: [
                      Color(
                        0x00000000,
                      ),
                      Color(
                        0x08000000,
                      ),
                      Color(
                        0x30080403,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left:
                    width < 340
                        ? 6
                        : 10,
                top:
                    (height -
                            edgeButtonSize) /
                        2,
                child:
                    _buildHeaderSquareButton(
                  size:
                      edgeButtonSize,
                  tooltip:
                      'Retour au Hall',
                  icon:
                      Icons
                          .arrow_back_rounded,
                  onPressed: () {
                    Navigator.pop(
                      context,
                    );
                  },
                ),
              ),
              if (_isProjectXpAdmin)
                Positioned(
                  left:
                      (width < 340
                              ? 6
                              : 10) +
                          edgeButtonSize +
                          4,
                  top:
                      (height - 30) /
                          2,
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child:
                        PopupMenuButton<String>(
                      tooltip:
                          'Administration Project XP',
                      color:
                          const Color(
                        0xff21150e,
                      ),
                      enabled:
                          !_resettingTavern,
                      padding:
                          EdgeInsets.zero,
                      iconSize: 17,
                      icon:
                          _resettingTavern
                              ? const SizedBox(
                                  width:
                                      15,
                                  height:
                                      15,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2,
                                    color:
                                        _tavernGold,
                                  ),
                                )
                              : const Icon(
                                  Icons
                                      .admin_panel_settings_outlined,
                                  color:
                                      _tavernGold,
                                ),
                      onSelected: (
                        String value,
                      ) {
                        if (value ==
                            'reset_tavern') {
                          _confirmResetTavern();
                        }
                      },
                      itemBuilder: (
                        BuildContext context,
                      ) {
                        return const [
                          PopupMenuItem<String>(
                            value:
                                'reset_tavern',
                            child: Row(
                              children: [
                                Icon(
                                  Icons
                                      .delete_sweep_outlined,
                                  color:
                                      Colors.redAccent,
                                ),
                                SizedBox(
                                  width:
                                      10,
                                ),
                                Text(
                                  'Réinitialiser le chat',
                                ),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
                ),
              Positioned(
                right:
                    phoneSlotWidth + 6,
                top:
                    (height -
                            presenceHeight) /
                        2,
                child:
                    _buildPresencePill(
                  height:
                      presenceHeight,
                ),
              ),
              // Le Communicateur global dessine le vrai téléphone dans ce slot.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width:
                      phoneSlotWidth,
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildHeaderSquareButton({
    required double size,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(
          0xe81b110b,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                12,
              ),
              border: Border.all(
                color: const Color(
                  0xff8c5a2d,
                ),
              ),
              boxShadow: const [
                BoxShadow(
                  color:
                      Color(
                    0x66000000,
                  ),
                  blurRadius: 7,
                  offset:
                      Offset(
                    0,
                    3,
                  ),
                ),
              ],
            ),
            child: Icon(
              icon,
              size:
                  size * 0.54,
              color:
                  _tavernGold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresencePill({
    double height = 40,
  }) {
    return StreamBuilder<int>(
      stream: OnlinePresenceService
          .instance
          .onlineCountStream,
      initialData:
          OnlinePresenceService
              .instance
              .currentCount,
      builder: (
        BuildContext context,
        AsyncSnapshot<int> snapshot,
      ) {
        final int count =
            snapshot.data ?? 0;

        return Container(
          height: height,
          padding:
              EdgeInsets.symmetric(
            horizontal:
                height < 37
                    ? 8
                    : 10,
          ),
          decoration: BoxDecoration(
            color:
                const Color(
              0xe61a110c,
            ),
            borderRadius:
                BorderRadius.circular(
              13,
            ),
            border: Border.all(
              color:
                  const Color(
                0xff76502d,
              ),
            ),
            boxShadow:
                const [
              BoxShadow(
                color:
                    Color(
                  0x66000000,
                ),
                blurRadius: 6,
                offset:
                    Offset(
                  0,
                  2,
                ),
              ),
            ],
          ),
          child: Row(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Container(
                width:
                    height < 37
                        ? 7
                        : 8,
                height:
                    height < 37
                        ? 7
                        : 8,
                decoration:
                    const BoxDecoration(
                  color:
                      Color(
                    0xff42d66b,
                  ),
                  shape:
                      BoxShape.circle,
                ),
              ),
              const SizedBox(
                width: 6,
              ),
              Icon(
                Icons
                    .people_alt_rounded,
                color:
                    Colors.white70,
                size:
                    height < 37
                        ? 15
                        : 17,
              ),
              const SizedBox(
                width: 5,
              ),
              Text(
                count.toString(),
                style: TextStyle(
                  color:
                      Colors.white,
                  fontSize:
                      height < 37
                          ? 11
                          : 12,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildContent() {
    if (_loadingChannels) {
      return const Center(
        child: CircularProgressIndicator(
          color: _tavernGold,
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

    return Container(
      color: _tavernBackground,
      child: Column(
        children: [
          _buildChannelSelector(),
          Expanded(
            child:
                _buildSelectedChannel(),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelSelector() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final bool threeChannelLayout =
            _channels.length == 3 &&
            width >= 340;

        final double selectorHeight =
            width < 340
                ? 70
                : 76;

        final Widget tabs;

        if (threeChannelLayout) {
          tabs = Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 7,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 30,
                  child:
                      _buildChannelTab(
                    channel:
                        _channels[0],
                    selected:
                        _channels[0]['id'] ==
                            _selectedChannel?['id'],
                  ),
                ),
                const SizedBox(
                  width: 6,
                ),
                Expanded(
                  flex: 42,
                  child:
                      _buildChannelTab(
                    channel:
                        _channels[1],
                    selected:
                        _channels[1]['id'] ==
                            _selectedChannel?['id'],
                  ),
                ),
                const SizedBox(
                  width: 6,
                ),
                Expanded(
                  flex: 28,
                  child:
                      _buildChannelTab(
                    channel:
                        _channels[2],
                    selected:
                        _channels[2]['id'] ==
                            _selectedChannel?['id'],
                  ),
                ),
              ],
            ),
          );
        } else {
          final double itemWidth =
              width < 300
                  ? 138
                  : width < 340
                      ? 150
                      : 184;

          tabs = ListView.separated(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 7,
            ),
            scrollDirection:
                Axis.horizontal,
            itemCount:
                _channels.length,
            separatorBuilder: (
              BuildContext context,
              int index,
            ) {
              return const SizedBox(
                width: 6,
              );
            },
            itemBuilder: (
              BuildContext context,
              int index,
            ) {
              final Map<String, dynamic> channel =
                  _channels[index];

              return SizedBox(
                width:
                    itemWidth,
                child:
                    _buildChannelTab(
                  channel:
                      channel,
                  selected:
                      channel['id'] ==
                          _selectedChannel?['id'],
                ),
              );
            },
          );
        }

        return Container(
          height:
              selectorHeight,
          padding:
              const EdgeInsets.symmetric(
            vertical: 7,
          ),
          decoration:
              const BoxDecoration(
            image:
                DecorationImage(
              image:
                  AssetImage(
                _tavernWoodStripAsset,
              ),
              fit:
                  BoxFit.cover,
            ),
            color:
                Color(
              0xff160e09,
            ),
            border:
                Border(
              top:
                  BorderSide(
                color:
                    Color(
                  0xff5a371d,
                ),
              ),
              bottom:
                  BorderSide(
                color:
                    Color(
                  0xff5a371d,
                ),
              ),
            ),
          ),
          child: tabs,
        );
      },
    );
  }


  Widget _buildChannelTab({
    required Map<String, dynamic> channel,
    required bool selected,
  }) {
    final String icon =
        channel['icon']
                ?.toString() ??
            '🍺';

    final String name =
        channel['name']
                ?.toString() ??
            'Channel';

    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final double iconSize =
            (width * 0.17)
                .clamp(
                  18.0,
                  25.0,
                )
                .toDouble();

        final double fontSize =
            (width * 0.092)
                .clamp(
                  10.5,
                  14.0,
                )
                .toDouble();

        return Material(
          color:
              Colors.transparent,
          child: InkWell(
            borderRadius:
                BorderRadius.circular(
              10,
            ),
            onTap: () {
              _selectChannel(
                channel,
              );
            },
            child:
                AnimatedContainer(
              duration:
                  const Duration(
                milliseconds:
                    180,
              ),
              decoration:
                  BoxDecoration(
                image:
                    const DecorationImage(
                  image:
                      AssetImage(
                    _tavernTabPanelAsset,
                  ),
                  fit:
                      BoxFit.cover,
                  filterQuality:
                      FilterQuality.medium,
                ),
                borderRadius:
                    BorderRadius.circular(
                  10,
                ),
                border:
                    Border.all(
                  color:
                      selected
                          ? _tavernGold
                          : const Color(
                              0xff5b3a22,
                            ),
                  width:
                      selected
                          ? 1.6
                          : 1,
                ),
                boxShadow: [
                  if (selected)
                    const BoxShadow(
                      color:
                          Color(
                        0x40ffbd4a,
                      ),
                      blurRadius:
                          7,
                    ),
                ],
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child:
                        DecoratedBox(
                      decoration:
                          BoxDecoration(
                        gradient:
                            LinearGradient(
                          begin:
                              Alignment.topCenter,
                          end:
                              Alignment.bottomCenter,
                          colors: [
                            Color(
                              0x05000000,
                            ),
                            Color(
                              0x3d000000,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal:
                            7,
                      ),
                      child: FittedBox(
                        fit:
                            BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Text(
                              icon,
                              style:
                                  TextStyle(
                                fontSize:
                                    iconSize,
                              ),
                            ),
                            SizedBox(
                              width:
                                  width <
                                          120
                                      ? 4
                                      : 7,
                            ),
                            Text(
                              name,
                              maxLines:
                                  1,
                              style:
                                  TextStyle(
                                color:
                                    selected
                                        ? _tavernGold
                                        : const Color(
                                            0xffded2c7,
                                          ),
                                fontSize:
                                    fontSize,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 3,
                      child:
                          Container(
                        height: 2.5,
                        decoration:
                            BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(
                            99,
                          ),
                          gradient:
                              const LinearGradient(
                            colors: [
                              Color(
                                0x00b15cff,
                              ),
                              _tavernPurple,
                              Color(
                                0x00b15cff,
                              ),
                            ],
                          ),
                          boxShadow:
                              const [
                            BoxShadow(
                              color:
                                  Color(
                                0x88b15cff,
                              ),
                              blurRadius:
                                  5,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
        _buildDiscussionHeader(),
        Expanded(
          child:
              StreamBuilder<List<Map<String, dynamic>>>(
            key:
                ValueKey(
              channelId,
            ),
            stream:
                messageStream,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
            ) {
              if (snapshot.connectionState ==
                      ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child:
                      CircularProgressIndicator(
                    color:
                        _tavernGold,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      24,
                    ),
                    child: Text(
                      'Impossible de charger les messages.\n'
                      '${snapshot.error}',
                      textAlign:
                          TextAlign.center,
                    ),
                  ),
                );
              }

              final List<Map<String, dynamic>> messages =
                  snapshot.data ??
                      <Map<String, dynamic>>[];

              final String pendingContent =
                  _pendingMessageContent
                          ?.trim() ??
                      '';

              final bool hasPendingMessage =
                  pendingContent.isNotEmpty &&
                      _pendingMessageChannelId ==
                          channelId;

              final int renderedItemCount =
                  messages.length +
                      (hasPendingMessage
                          ? 1
                          : 0);

              if (renderedItemCount !=
                  _lastAutoScrollItemCount) {
                _lastAutoScrollItemCount =
                    renderedItemCount;

                if (renderedItemCount > 0) {
                  WidgetsBinding
                      .instance
                      .addPostFrameCallback(
                    (_) {
                      _scrollToBottom();
                    },
                  );
                }
              }

              return _buildChatStage(
                messages: messages,
                hasPendingMessage:
                    hasPendingMessage,
                pendingContent:
                    pendingContent,
              );
            },
          ),
        ),
        _buildMessageComposer(),
      ],
    );
  }

  Widget _buildDiscussionHeader() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final double height =
            width < 340
                ? 40
                : 44;

        final double fontSize =
            width < 340
                ? 11.5
                : 13;

        return Container(
          height: height,
          decoration:
              const BoxDecoration(
            image:
                DecorationImage(
              image:
                  AssetImage(
                _tavernWallAsset,
              ),
              fit:
                  BoxFit.cover,
            ),
            border:
                Border(
              bottom:
                  BorderSide(
                color:
                    Color(
                  0xff4e321d,
                ),
              ),
            ),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Divider(
                  indent: 16,
                  endIndent: 10,
                  color:
                      Color(
                    0xff68482c,
                  ),
                ),
              ),
              Text(
                'DISCUSSION GÉNÉRALE',
                maxLines: 1,
                style:
                    TextStyle(
                  color:
                      const Color(
                    0xffc999ef,
                  ),
                  fontSize:
                      fontSize,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing:
                      0.45,
                  shadows:
                      const [
                    Shadow(
                      color:
                          Color(
                        0x66000000,
                      ),
                      blurRadius:
                          3,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding:
                    EdgeInsets.symmetric(
                  horizontal: 7,
                ),
                child: Text(
                  '◆',
                  style:
                      TextStyle(
                    color:
                        _tavernGold,
                    fontSize:
                        7,
                  ),
                ),
              ),
              const Expanded(
                child: Divider(
                  indent: 4,
                  endIndent: 16,
                  color:
                      Color(
                    0xff68482c,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildChatStage({
    required List<Map<String, dynamic>> messages,
    required bool hasPendingMessage,
    required String pendingContent,
  }) {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final double height =
            constraints.maxHeight;

        double shelfWidth =
            (width * 0.105)
                .clamp(
                  24.0,
                  70.0,
                )
                .toDouble();

        if (width < 290 ||
            height < 260) {
          shelfWidth = 0;
        } else if (width < 330) {
          shelfWidth =
              shelfWidth
                  .clamp(
                    24.0,
                    30.0,
                  )
                  .toDouble();
        }

        final double dpr =
            MediaQuery.devicePixelRatioOf(
          context,
        );

        final int shelfCacheWidth =
            shelfWidth <= 0
                ? 64
                : (shelfWidth *
                        dpr *
                        1.15)
                    .round()
                    .clamp(
                      64,
                      160,
                    )
                    .toInt();

        final Widget center;

        if (messages.isEmpty &&
            !hasPendingMessage) {
          center =
              _buildEmptyState();
        } else {
          center =
              ListView.separated(
            controller:
                _messageScrollController,
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior
                    .onDrag,
            padding:
                EdgeInsets.fromLTRB(
              width < 350
                  ? 7
                  : 11,
              12,
              width < 350
                  ? 7
                  : 11,
              20,
            ),
            itemCount:
                messages.length +
                    (hasPendingMessage
                        ? 1
                        : 0),
            separatorBuilder: (
              BuildContext context,
              int index,
            ) {
              return SizedBox(
                height:
                    width < 350
                        ? 8
                        : 10,
              );
            },
            itemBuilder: (
              BuildContext context,
              int index,
            ) {
              if (index >=
                  messages.length) {
                return _buildPendingMessage(
                  pendingContent,
                );
              }

              return _buildMessage(
                messages[index],
              );
            },
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration:
                  const BoxDecoration(
                color:
                    _tavernPanel,
                image:
                    DecorationImage(
                  image:
                      AssetImage(
                    _tavernWallAsset,
                  ),
                  fit:
                      BoxFit.cover,
                  repeat:
                      ImageRepeat.repeatY,
                ),
              ),
            ),
            const DecoratedBox(
              decoration:
                  BoxDecoration(
                gradient:
                    LinearGradient(
                  begin:
                      Alignment.topCenter,
                  end:
                      Alignment.bottomCenter,
                  colors: [
                    Color(
                      0x50000000,
                    ),
                    Color(
                      0x78090503,
                    ),
                    Color(
                      0x61090503,
                    ),
                    Color(
                      0x79090503,
                    ),
                  ],
                  stops: [
                    0,
                    0.22,
                    0.76,
                    1,
                  ],
                ),
              ),
            ),
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                if (shelfWidth > 0)
                  SizedBox(
                    width:
                        shelfWidth,
                    child: Image.asset(
                      _tavernShelfLeftAsset,
                      fit:
                          BoxFit.fill,
                      alignment:
                          Alignment.topCenter,
                      cacheWidth:
                          shelfCacheWidth,
                      filterQuality:
                          FilterQuality.medium,
                      gaplessPlayback:
                          true,
                    ),
                  ),
                Expanded(
                  child:
                      DecoratedBox(
                    decoration:
                        BoxDecoration(
                      gradient:
                          const LinearGradient(
                        begin:
                            Alignment.topCenter,
                        end:
                            Alignment.bottomCenter,
                        colors: [
                          Color(
                            0x7f0c0806,
                          ),
                          Color(
                            0xb30c0806,
                          ),
                          Color(
                            0xa60c0806,
                          ),
                          Color(
                            0xc40c0806,
                          ),
                        ],
                      ),
                      border:
                          Border(
                        left:
                            BorderSide(
                          color:
                              Colors.black
                                  .withValues(
                            alpha:
                                0.28,
                          ),
                        ),
                        right:
                            BorderSide(
                          color:
                              Colors.black
                                  .withValues(
                            alpha:
                                0.28,
                          ),
                        ),
                      ),
                    ),
                    child: center,
                  ),
                ),
                if (shelfWidth > 0)
                  SizedBox(
                    width:
                        shelfWidth,
                    child: Image.asset(
                      _tavernShelfRightAsset,
                      fit:
                          BoxFit.fill,
                      alignment:
                          Alignment.topCenter,
                      cacheWidth:
                          shelfCacheWidth,
                      filterQuality:
                          FilterQuality.medium,
                      gaplessPlayback:
                          true,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }


  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final double height =
            constraints.maxHeight;

        final bool compact =
            width < 250 ||
            height < 420;

        final double maxCardWidth =
            (width * 0.84)
                .clamp(
                  190.0,
                  300.0,
                )
                .toDouble();

        final double beerSize =
            compact
                ? 47
                : 54;

        return Center(
          child:
              SingleChildScrollView(
            padding:
                EdgeInsets.symmetric(
              horizontal:
                  compact
                      ? 8
                      : 14,
              vertical:
                  compact
                      ? 10
                      : 16,
            ),
            child:
                ConstrainedBox(
              constraints:
                  BoxConstraints(
                maxWidth:
                    maxCardWidth,
              ),
              child: Container(
                padding:
                    EdgeInsets.fromLTRB(
                  compact
                      ? 14
                      : 18,
                  compact
                      ? 14
                      : 18,
                  compact
                      ? 14
                      : 18,
                  compact
                      ? 14
                      : 16,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xd624150e,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                  border:
                      Border.all(
                    color:
                        const Color(
                      0xff7a4d29,
                    ),
                    width:
                        1,
                  ),
                  boxShadow:
                      const [
                    BoxShadow(
                      color:
                          Color(
                        0x50000000,
                      ),
                      blurRadius:
                          14,
                      offset:
                          Offset(
                        0,
                        6,
                      ),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Container(
                      width:
                          beerSize,
                      height:
                          beerSize,
                      alignment:
                          Alignment.center,
                      decoration:
                          BoxDecoration(
                        shape:
                            BoxShape.circle,
                        color:
                            const Color(
                          0xff1d120c,
                        ),
                        border:
                            Border.all(
                          color:
                              _tavernGoldDeep,
                        ),
                      ),
                      child: Text(
                        '🍺',
                        style:
                            TextStyle(
                          fontSize:
                              compact
                                  ? 27
                                  : 31,
                        ),
                      ),
                    ),
                    SizedBox(
                      height:
                          compact
                              ? 11
                              : 13,
                    ),
                    Text(
                      'Le Comptoir est encore silencieux...',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            _tavernGold,
                        fontSize:
                            compact
                                ? 14
                                : 16,
                        fontWeight:
                            FontWeight.w800,
                        height:
                            1.22,
                      ),
                    ),
                    SizedBox(
                      height:
                          compact
                              ? 6
                              : 8,
                    ),
                    Text(
                      'Sois le premier aventurier à parler.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.white
                                .withValues(
                          alpha:
                              0.60,
                        ),
                        fontSize:
                            compact
                                ? 11.5
                                : 13,
                        height:
                            1.32,
                      ),
                    ),
                    SizedBox(
                      height:
                          compact
                              ? 10
                              : 13,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child:
                              Container(
                            height:
                                1,
                            color:
                                const Color(
                              0xff5d3b22,
                            ),
                          ),
                        ),
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(
                            horizontal:
                                8,
                          ),
                          child:
                              Text(
                            '✦',
                            style:
                                TextStyle(
                              color:
                                  _tavernGold,
                              fontSize:
                                  10,
                            ),
                          ),
                        ),
                        Expanded(
                          child:
                              Container(
                            height:
                                1,
                            color:
                                const Color(
                              0xff5d3b22,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height:
                          compact
                              ? 8
                              : 10,
                    ),
                    Text(
                      'Ici, chacun a une histoire à partager.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            const Color(
                              0xffd09b67,
                            )
                                .withValues(
                          alpha:
                              0.76,
                        ),
                        fontSize:
                            compact
                                ? 10.5
                                : 11.5,
                        fontStyle:
                            FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildChannelTitle(
    Map<String, dynamic> channel,
  ) {
    final String icon =
        channel['icon']?.toString() ??
            '';

    final String name =
        channel['name']?.toString() ??
            '';

    final String description =
        channel['description']
                ?.toString() ??
            '';

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 14,
      ),
      decoration:
          const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            _tavernWallAsset,
          ),
          fit: BoxFit.cover,
        ),
        border: Border(
          bottom: BorderSide(
            color:
                Color(
              0xff4b301c,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            icon,
            style:
                const TextStyle(
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
                  style:
                      const TextStyle(
                    color:
                        _tavernGold,
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                if (description
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    description,
                    style:
                        const TextStyle(
                      color:
                          Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingMessage(
    String content,
  ) {
    final String time =
        _formatMessageTime(
      _pendingMessageCreatedAt
          ?.toIso8601String(),
    );

    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final bool compact =
            width < 245;

        final double avatarSize =
            (width * 0.135)
                .clamp(
                  34.0,
                  46.0,
                )
                .toDouble();

        return Opacity(
          opacity: 0.76,
          child: Align(
            alignment:
                Alignment.centerLeft,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth:
                    560,
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width:
                        avatarSize,
                    height:
                        avatarSize,
                    alignment:
                        Alignment.center,
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xff2c1a11,
                      ),
                      shape:
                          BoxShape.circle,
                      border:
                          Border.all(
                        color:
                            _tavernGoldDeep,
                      ),
                    ),
                    child:
                        Icon(
                      Icons
                          .send_rounded,
                      size:
                          avatarSize *
                              0.42,
                      color:
                          _tavernGold,
                    ),
                  ),
                  SizedBox(
                    width:
                        compact
                            ? 6
                            : 8,
                  ),
                  Flexible(
                    child:
                        Container(
                      padding:
                          EdgeInsets.fromLTRB(
                        compact
                            ? 8
                            : 11,
                        compact
                            ? 7
                            : 9,
                        compact
                            ? 8
                            : 11,
                        compact
                            ? 7
                            : 9,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xdc21150f,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          13,
                        ),
                        border:
                            Border.all(
                          color:
                              const Color(
                            0xff7c5731,
                          ),
                        ),
                      ),
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              const Text(
                                'Vous',
                                style:
                                    TextStyle(
                                  color:
                                      _tavernGold,
                                  fontWeight:
                                      FontWeight.w800,
                                  fontSize:
                                      13,
                                ),
                              ),
                              if (time
                                  .isNotEmpty) ...[
                                const SizedBox(
                                  width:
                                      7,
                                ),
                                Text(
                                  time,
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.white38,
                                    fontSize:
                                        10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(
                            height:
                                4,
                          ),
                          Text(
                            content,
                            style:
                                TextStyle(
                              color:
                                  Colors.white,
                              fontSize:
                                  compact
                                      ? 12.5
                                      : 13.5,
                              height:
                                  1.32,
                            ),
                          ),
                          const SizedBox(
                            height:
                                5,
                          ),
                          const Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              SizedBox(
                                width:
                                    9,
                                height:
                                    9,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      1.2,
                                  color:
                                      _tavernGold,
                                ),
                              ),
                              SizedBox(
                                width:
                                    5,
                              ),
                              Text(
                                'Envoi…',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.white54,
                                  fontSize:
                                      9.5,
                                  fontStyle:
                                      FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Widget _buildMessage(
    Map<String, dynamic> message,
  ) {
    final String authorId =
        message['author_id']
                ?.toString() ??
            '';

    final Map<String, dynamic>? profile =
        _asStringDynamicMap(
      message[
          'author_profile'],
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
        message['content']
                ?.toString() ??
            '';

    final String createdAt =
        _formatMessageTime(
      message['created_at']
          ?.toString(),
    );

    final Color accent =
        _authorAccent(
      authorId,
    );

    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final double avatarSize =
            (width * 0.135)
                .clamp(
                  34.0,
                  46.0,
                )
                .toDouble();

        final bool compact =
            width < 245;

        return Align(
          alignment:
              Alignment.centerLeft,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 560,
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior:
                      HitTestBehavior.opaque,
                  onTap: () {
                    _openPlayerCard(
                      authorId:
                          authorId,
                      profile:
                          profile,
                    );
                  },
                  child:
                      _buildAuthorAvatar(
                    profile:
                        profile,
                    authorId:
                        authorId,
                    displayName:
                        authorName,
                    size:
                        avatarSize,
                    accent:
                        accent,
                  ),
                ),
                SizedBox(
                  width:
                      compact
                          ? 6
                          : 8,
                ),
                Flexible(
                  child: Container(
                    padding:
                        EdgeInsets.fromLTRB(
                      compact
                          ? 8
                          : 11,
                      compact
                          ? 7
                          : 9,
                      compact
                          ? 8
                          : 11,
                      compact
                          ? 7
                          : 9,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xdc17100d,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        13,
                      ),
                      border:
                          Border.all(
                        color:
                            accent
                                .withValues(
                          alpha:
                              0.42,
                        ),
                      ),
                      boxShadow:
                          const [
                        BoxShadow(
                          color:
                              Color(
                            0x3d000000,
                          ),
                          blurRadius:
                              7,
                          offset:
                              Offset(
                            0,
                            3,
                          ),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Flexible(
                              child:
                                  GestureDetector(
                                behavior:
                                    HitTestBehavior.opaque,
                                onTap:
                                    () {
                                  _openPlayerCard(
                                    authorId:
                                        authorId,
                                    profile:
                                        profile,
                                  );
                                },
                                child:
                                    Text(
                                  authorName,
                                  maxLines:
                                      1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style:
                                      TextStyle(
                                    color:
                                        accent,
                                    fontWeight:
                                        FontWeight.w800,
                                    fontSize:
                                        compact
                                            ? 11.5
                                            : 13,
                                  ),
                                ),
                              ),
                            ),
                            if (createdAt
                                .isNotEmpty) ...[
                              const SizedBox(
                                width:
                                    7,
                              ),
                              Text(
                                createdAt,
                                style:
                                    TextStyle(
                                  color:
                                      Colors.white
                                          .withValues(
                                    alpha:
                                        0.40,
                                  ),
                                  fontSize:
                                      compact
                                          ? 9
                                          : 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(
                          height:
                              4,
                        ),
                        Text(
                          content,
                          style:
                              TextStyle(
                            color:
                                const Color(
                              0xfff4eee9,
                            ),
                            fontSize:
                                compact
                                    ? 12.5
                                    : 13.5,
                            height:
                                1.32,
                          ),
                        ),
                      ],
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


  Widget _buildAuthorAvatar({
    required Map<String, dynamic>? profile,
    required String authorId,
    required String displayName,
    double size = 48,
    Color? accent,
  }) {
    final Color resolvedAccent =
        accent ??
            _authorAccent(
              authorId,
            );

    final String avatarUrl =
        profile?['avatar_url']
                ?.toString()
                .trim() ??
            '';

    Widget content;

    if (avatarUrl.isNotEmpty) {
      content = Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) {
          return _buildAvatarFallback(
            displayName,
            size: size,
            accent:
                resolvedAccent,
          );
        },
      );
    } else {
      final AvatarModel? avatar =
          _avatarFromProfile(
        profile,
        authorId,
      );

      if (avatar == null) {
        return _buildAvatarFallback(
          displayName,
          size: size,
          accent:
              resolvedAccent,
        );
      }

      content = OverflowBox(
        alignment:
            Alignment.topCenter,
        minWidth: size,
        maxWidth: size,
        minHeight:
            size * 1.5,
        maxHeight:
            size * 1.5,
        child: AvatarRenderer(
          avatar: avatar,
          size: size,
          showFrame: false,
          compactHeadCrop: true,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding:
          const EdgeInsets.all(
        2,
      ),
      decoration:
          BoxDecoration(
        shape: BoxShape.circle,
        color:
            const Color(
          0xff1b110c,
        ),
        border: Border.all(
          color:
              resolvedAccent
                  .withValues(
            alpha: 0.82,
          ),
          width: 1.4,
        ),
        boxShadow: const [
          BoxShadow(
            color:
                Color(
              0x55000000,
            ),
            blurRadius: 8,
            offset:
                Offset(
              0,
              3,
            ),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: content,
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(
    String displayName, {
    double size = 48,
    Color? accent,
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

    final Color resolvedAccent =
        accent ??
            _tavernGoldDeep;

    return Container(
      width: size,
      height: size,
      alignment:
          Alignment.center,
      decoration:
          BoxDecoration(
        shape: BoxShape.circle,
        color:
            const Color(
          0xff3a2416,
        ),
        border: Border.all(
          color:
              resolvedAccent,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color:
              resolvedAccent,
          fontSize:
              size * 0.40,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }

  Color _authorAccent(
    String authorId,
  ) {
    const List<Color> palette =
        <Color>[
      Color(
        0xffc56cff,
      ),
      Color(
        0xff65ce72,
      ),
      Color(
        0xff53a6ff,
      ),
      Color(
        0xffff9b45,
      ),
      Color(
        0xffffcf5e,
      ),
      Color(
        0xff66d5ca,
      ),
      Color(
        0xffff728d,
      ),
    ];

    if (authorId.isEmpty) {
      return _tavernGold;
    }

    int hash = 0;

    for (
      final int codeUnit
      in authorId.codeUnits
    ) {
      hash =
          ((hash * 31) +
                  codeUnit) &
              0x7fffffff;
    }

    return palette[
      hash % palette.length
    ];
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
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width =
            constraints.maxWidth;

        final bool showPlus =
            width >= 326;

        final bool showEmoji =
            width >= 290;

        final double buttonSize =
            (width * 0.12)
                .clamp(
                  40.0,
                  50.0,
                )
                .toDouble();

        final double horizontalPadding =
            width < 340
                ? 6
                : 9;

        return Container(
          padding:
              EdgeInsets.fromLTRB(
            horizontalPadding,
            7,
            horizontalPadding,
            9,
          ),
          decoration:
              const BoxDecoration(
            image:
                DecorationImage(
              image:
                  AssetImage(
                _tavernWoodStripAsset,
              ),
              fit:
                  BoxFit.cover,
            ),
            border:
                Border(
              top:
                  BorderSide(
                color:
                    Color(
                  0xff6d4525,
                ),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Color(
                  0x88000000,
                ),
                blurRadius:
                    12,
                offset:
                    Offset(
                  0,
                  -3,
                ),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              if (showPlus) ...[
                _buildComposerButton(
                  size:
                      buttonSize,
                  icon:
                      Icons.add_rounded,
                  foreground:
                      _tavernGold,
                  onPressed: () {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(
                      const SnackBar(
                        duration:
                            Duration(
                          milliseconds:
                              1100,
                        ),
                        content:
                            Text(
                          'Les pièces jointes arriveront bientôt.',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(
                  width: 6,
                ),
              ],
              Expanded(
                child:
                    Container(
                  constraints:
                      const BoxConstraints(
                    minHeight:
                        44,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xe9150f0b,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      14,
                    ),
                    border:
                        Border.all(
                      color:
                          const Color(
                        0xff75502d,
                      ),
                    ),
                    boxShadow:
                        const [
                      BoxShadow(
                        color:
                            Color(
                          0x4a000000,
                        ),
                        blurRadius:
                            7,
                      ),
                    ],
                  ),
                  child:
                      TextField(
                    controller:
                        _messageController,
                    minLines: 1,
                    maxLines:
                        width < 330
                            ? 3
                            : 4,
                    maxLength:
                        2000,
                    textCapitalization:
                        TextCapitalization
                            .sentences,
                    textInputAction:
                        TextInputAction
                            .send,
                    scrollPadding:
                        const EdgeInsets.only(
                      bottom:
                          130,
                    ),
                    style:
                        TextStyle(
                      color:
                          const Color(
                        0xfff5eee8,
                      ),
                      fontSize:
                          width < 330
                              ? 13
                              : 14,
                    ),
                    cursorColor:
                        _tavernGold,
                    decoration:
                        InputDecoration(
                      counterText:
                          '',
                      hintText:
                          'Parler au Comptoir...',
                      hintStyle:
                          const TextStyle(
                        color:
                            Colors.white38,
                      ),
                      border:
                          InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(
                        horizontal:
                            width < 330
                                ? 11
                                : 13,
                        vertical:
                            11,
                      ),
                    ),
                    onTap: () {
                      WidgetsBinding
                          .instance
                          .addPostFrameCallback(
                        (_) {
                          _scrollToBottom();
                        },
                      );
                    },
                    onSubmitted:
                        (_) {
                      _sendMessage();
                    },
                  ),
                ),
              ),
              if (showEmoji) ...[
                const SizedBox(
                  width: 6,
                ),
                _buildComposerButton(
                  size:
                      buttonSize,
                  icon:
                      Icons
                          .sentiment_satisfied_alt_rounded,
                  foreground:
                      _tavernGold,
                  onPressed: () {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(
                      const SnackBar(
                        duration:
                            Duration(
                          milliseconds:
                              1100,
                        ),
                        content:
                            Text(
                          'Le sélecteur d’emojis arrivera bientôt.',
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(
                width: 6,
              ),
              SizedBox(
                width:
                    buttonSize,
                height:
                    buttonSize,
                child:
                    FilledButton(
                  style:
                      FilledButton.styleFrom(
                    padding:
                        EdgeInsets.zero,
                    backgroundColor:
                        const Color(
                      0xff6b3c88,
                    ),
                    disabledBackgroundColor:
                        const Color(
                      0xff3e2c42,
                    ),
                    foregroundColor:
                        _tavernGold,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        13,
                      ),
                      side:
                          const BorderSide(
                        color:
                            Color(
                          0xffd4a548,
                        ),
                        width:
                            1.4,
                      ),
                    ),
                    elevation:
                        2,
                  ),
                  onPressed:
                      _sendingMessage
                          ? null
                          : _sendMessage,
                  child:
                      _sendingMessage
                          ? SizedBox(
                              width:
                                  buttonSize *
                                      0.38,
                              height:
                                  buttonSize *
                                      0.38,
                              child:
                                  const CircularProgressIndicator(
                                strokeWidth:
                                    2,
                                color:
                                    _tavernGold,
                              ),
                            )
                          : Icon(
                              Icons
                                  .send_rounded,
                              size:
                                  buttonSize *
                                      0.50,
                            ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildComposerButton({
    required double size,
    required IconData icon,
    required Color foreground,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: OutlinedButton(
        onPressed: onPressed,
        style:
            OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor:
              foreground,
          backgroundColor:
              const Color(
            0xe31c120d,
          ),
          side:
              const BorderSide(
            color:
                Color(
              0xff76502d,
            ),
          ),
          shape:
              BeveledRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              9,
            ),
          ),
        ),
        child: Icon(
          icon,
          size: 24,
        ),
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
