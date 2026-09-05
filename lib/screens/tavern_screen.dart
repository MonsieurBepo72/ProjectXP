import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/avatar_model.dart';
import '../services/content_moderation_service.dart';
import '../services/friend_service.dart';
import '../services/online_presence_service.dart';
import '../services/profile_storage.dart';
import '../services/project_xp_admin_service.dart';
import '../services/project_xp_message_send_result.dart';
import '../services/supabase_service.dart';
import '../services/tavern_profile_service.dart';
import '../services/tavern_service.dart';
import '../widgets/avatar_renderer.dart';
import '../widgets/hall_home_button.dart';

class TavernScreen extends StatefulWidget {
  const TavernScreen({
    super.key,
  });

  @override
  State<TavernScreen> createState() => _TavernScreenState();
}

class _TavernScreenState extends State<TavernScreen> {

  // ===========================================================================
  // TAVERNE V8.2.1 — NAVIGATION HALL COHÉRENTE
  // ===========================================================================
  //
  // Le décor lourd est maintenant porté par des images dédiées : header,
  // étagères du Comptoir, bois central, fond sobre des autres sections et
  // cadre de saisie. Flutter ne redessine plus la taverne : il gère seulement
  // ce qui doit vivre et bouger (présence, tabs, swipe, messages, profils,
  // modération et saisie).

  static const String _tavernHeaderAsset =
      'assets/images/tavern/v8_header.jpg';

  static const String _tavernTabSelectedAsset =
      'assets/images/tavern/v8_tab_selected.png';

  static const String _tavernTabIdleAsset =
      'assets/images/tavern/v8_tab_idle.png';

  static const String _tavernShelfLeftAsset =
      'assets/images/tavern/v8_shelf_left.jpg';

  static const String _tavernShelfRightAsset =
      'assets/images/tavern/v8_shelf_right.jpg';

  static const String _tavernCenterWoodAsset =
      'assets/images/tavern/v8_center_wood.jpg';

  static const String _tavernSimpleBackgroundAsset =
      'assets/images/tavern/v8_simple_bg.jpg';

  static const String _tavernComposerAsset =
      'assets/images/tavern/v8_composer.jpg';

  static const String _tavernTabsBackgroundAsset =
      'assets/images/tavern/v8_tabs_bg.jpg';


  static const Color _tavernBackground =
      Color(0xff0d0806);

  static const Color _tavernGold =
      Color(0xffffca63);

  static const Color _tavernGoldDeep =
      Color(0xff9e642b);

  static const double _maxTavernWidth = 760;

  static const List<Map<String, String>> _chatColorOptions =
      <Map<String, String>>[
    {'name': 'Violet arcanique', 'hex': '#C56CFF'},
    {'name': 'Or héroïque', 'hex': '#FFCF5E'},
    {'name': 'Vert rôdeur', 'hex': '#65CE72'},
    {'name': 'Bleu mana', 'hex': '#53A6FF'},
    {'name': 'Orange forge', 'hex': '#FF9B45'},
    {'name': 'Turquoise esprit', 'hex': '#66D5CA'},
    {'name': 'Rose mystique', 'hex': '#FF728D'},
    {'name': 'Rouge dragon', 'hex': '#E86666'},
  ];

  static const List<Map<String, String>> _tavernSections =
      <Map<String, String>>[
    <String, String>{
      'slug': 'comptoir',
      'label': 'Comptoir',
      'icon': '🍺',
      'title': 'DISCUSSION GÉNÉRALE',
      'description': 'Le grand salon public de Project XP.',
    },
    <String, String>{
      'slug': 'quetes',
      'label': 'Quêtes & Aventures',
      'icon': '⚔️',
      'title': 'QUÊTES & AVENTURES',
      'description': 'Quêtes communautaires et aventures à plusieurs.',
    },
    <String, String>{
      'slug': 'marche',
      'label': 'Marché',
      'icon': '🛒',
      'title': 'MARCHÉ',
      'description': 'Échanges, annonces et trouvailles des aventuriers.',
    },
    <String, String>{
      'slug': 'des_jeux',
      'label': 'Dés & Jeux',
      'icon': '🎲',
      'title': 'DÉS & JEUX',
      'description': 'Mini-jeux, défis et hasard entre aventuriers.',
    },
    <String, String>{
      'slug': 'hauts_faits',
      'label': 'Hauts Faits',
      'icon': '🏆',
      'title': 'HAUTS FAITS',
      'description': 'Succès, exploits et progression de la communauté.',
    },
  ];

  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _messageScrollController =
      ScrollController();

  final PageController _sectionPageController =
      PageController();

  final ScrollController _sectionTabScrollController =
      ScrollController();

  final List<GlobalKey> _sectionTabKeys =
      List<GlobalKey>.generate(
    _tavernSections.length,
    (_) => GlobalKey(),
  );

  int _selectedSectionIndex = 0;

  bool _loadingChannels = true;
  bool _sendingMessage = false;
  bool _isProjectXpAdmin = false;
  bool _resettingTavern = false;
  final Set<String> _deletingMessageIds = <String>{};

  bool _didPrecacheTavernAssets = false;
  bool _savingChatColor = false;
  String _currentChatColorHex = '#C56CFF';
  int _lastAutoScrollItemCount = -1;
  double _lastKeyboardInset = 0;

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
    unawaited(_loadCurrentChatColor());

    // La Taverne dessine son décor derrière la barre d'état Android.
    // Les autres écrans restent protégés par leurs propres SafeArea.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      ),
    );

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
          _tavernTabSelectedAsset,
          _tavernTabIdleAsset,
          _tavernShelfLeftAsset,
          _tavernShelfRightAsset,
          _tavernCenterWoodAsset,
          _tavernSimpleBackgroundAsset,
          _tavernComposerAsset,
          _tavernTabsBackgroundAsset,
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
    _sectionPageController.dispose();
    _sectionTabScrollController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // COULEUR PERSONNELLE DU CHAT
  // ===========================================================================

  Future<void> _loadCurrentChatColor() async {
    try {
      final Map<String, dynamic> profile =
          await ProfileStorage.loadProfile();

      final String stored =
          profile['chatColor']?.toString().trim() ?? '';

      final Color? parsed = _parseProfileColor(stored);

      if (!mounted || parsed == null) {
        return;
      }

      setState(() {
        _currentChatColorHex = _colorToHex(parsed);
      });
    } catch (_) {
      // Le fallback violet reste volontairement utilisable hors-ligne.
    }
  }

  String _colorToHex(Color color) {
    final int value = color.toARGB32() & 0x00FFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color get _currentChatAccent =>
      _parseProfileColor(_currentChatColorHex) ??
      const Color(0xffc56cff);

  Future<void> _openChatColorPicker() async {
    if (_savingChatColor) {
      return;
    }

    String? selected = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff21150e),
          title: const Text(
            'Ma couleur de chat',
            style: TextStyle(
              color: _tavernGold,
            ),
          ),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Cette couleur concerne uniquement ton profil : '
                  'pseudo, avatar et contour de tes propres messages.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 11,
                  runSpacing: 11,
                  alignment: WrapAlignment.center,
                  children: _chatColorOptions.map(
                    (Map<String, String> option) {
                      final String hex =
                          option['hex'] ?? '#C56CFF';
                      final String name =
                          option['name'] ?? 'Couleur';
                      final Color color =
                          _parseProfileColor(hex) ??
                          const Color(0xffc56cff);
                      final bool active =
                          _currentChatColorHex.toUpperCase() ==
                          hex.toUpperCase();

                      return Tooltip(
                        message: name,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            Navigator.pop(
                              dialogContext,
                              hex,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(
                              milliseconds: 150,
                            ),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(
                                color: active
                                    ? Colors.white
                                    : Colors.white24,
                                width: active ? 2.5 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(
                                    alpha: 0.24,
                                  ),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: active
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                        '__custom__',
                      );
                    },
                    icon: const Icon(
                      Icons.tune_rounded,
                    ),
                    label: const Text(
                      'COULEUR PERSONNALISÉE',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );

    if (selected == '__custom__' && mounted) {
      selected = await _openCustomChatColorPicker();
    }

    if (selected == null || !mounted) {
      return;
    }

    final Color? parsed = _parseProfileColor(selected);

    if (parsed == null) {
      return;
    }

    final String normalized = _colorToHex(parsed);

    if (normalized == _currentChatColorHex.toUpperCase()) {
      return;
    }

    setState(() {
      _savingChatColor = true;
      _currentChatColorHex = normalized;
    });

    final bool saved =
        await ProfileStorage.saveChatColor(normalized);

    final bool synced = saved
        ? await TavernProfileService.syncCurrentProfile()
        : false;

    if (!mounted) {
      return;
    }

    setState(() {
      _savingChatColor = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(
          milliseconds: 1200,
        ),
        content: Text(
          saved && synced
              ? 'Ta couleur de chat est synchronisée.'
              : saved
                  ? 'Couleur enregistrée. Synchronisation en attente.'
                  : 'Impossible d’enregistrer la couleur.',
        ),
      ),
    );
  }

  Future<String?> _openCustomChatColorPicker() async {
    final int initial = _currentChatAccent.toARGB32();

    double red = ((initial >> 16) & 0xff).toDouble();
    double green = ((initial >> 8) & 0xff).toDouble();
    double blue = (initial & 0xff).toDouble();

    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            void Function(void Function()) setDialogState,
          ) {
            final int r =
                red.round().clamp(0, 255).toInt();
            final int g =
                green.round().clamp(0, 255).toInt();
            final int b =
                blue.round().clamp(0, 255).toInt();
            final Color preview = Color.fromARGB(
              255,
              r,
              g,
              b,
            );
            final String hex = _colorToHex(preview);

            Widget slider(
              String label,
              double value,
              ValueChanged<double> onChanged,
            ) {
              return Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: value,
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: onChanged,
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      value.round().toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xff21150e),
              title: const Text(
                'Couleur personnalisée',
                style: TextStyle(
                  color: _tavernGold,
                ),
              ),
              content: SizedBox(
                width: 310,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: preview,
                        border: Border.all(
                          color: Colors.white70,
                          width: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hex,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    slider(
                      'R',
                      red,
                      (double value) {
                        setDialogState(() {
                          red = value;
                        });
                      },
                    ),
                    slider(
                      'V',
                      green,
                      (double value) {
                        setDialogState(() {
                          green = value;
                        });
                      },
                    ),
                    slider(
                      'B',
                      blue,
                      (double value) {
                        setDialogState(() {
                          blue = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      hex,
                    );
                  },
                  child: const Text('Appliquer'),
                ),
              ],
            );
          },
        );
      },
    );
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

  Future<void> _confirmDeleteTavernMessage(
    Map<String, dynamic> message,
  ) async {
    if (!_isProjectXpAdmin) {
      return;
    }

    final String messageId =
        message['id']?.toString().trim() ?? '';

    if (messageId.isEmpty ||
        _deletingMessageIds.contains(messageId)) {
      return;
    }

    final Map<String, dynamic>? profile =
        _asStringDynamicMap(message['author_profile']);

    final String displayName =
        profile?['display_name']?.toString().trim() ?? '';

    final String authorId =
        message['author_id']?.toString().trim() ?? '';

    final String authorName = displayName.isNotEmpty
        ? displayName
        : _fallbackAuthorName(authorId);

    final String content =
        message['content']?.toString().trim() ?? '';

    final String preview = content.length > 110
        ? '${content.substring(0, 110)}…'
        : content;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xff21150e),
          title: const Text(
            'Supprimer ce message ?',
            style: TextStyle(
              color: Color(0xffffd27a),
            ),
          ),
          content: Text(
            '$authorName\n\n'
            '${preview.isEmpty ? 'Message sans contenu.' : preview}\n\n'
            'Cette action est réservée aux administrateurs et est définitive.',
            style: const TextStyle(
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
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(
                Icons.delete_outline_rounded,
              ),
              label: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _deletingMessageIds.add(messageId);
    });

    final bool deleted =
        await ProjectXpAdminService.deleteTavernMessage(
      messageId: messageId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _deletingMessageIds.remove(messageId);
    });

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Suppression impossible. Vérifie le RPC et les droits administrateur.',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(milliseconds: 900),
        content: Text('Message supprimé.'),
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

    FocusManager.instance.primaryFocus?.unfocus();

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

    if (result.rateLimited) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu envoies des messages trop rapidement. Réessaie dans quelques secondes.',
          ),
        ),
      );

      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Impossible d’envoyer le message pour le moment.',
        ),
      ),
    );
  }

  void _scrollToBottom({
    bool animated = true,
  }) {
    if (!_messageScrollController.hasClients) {
      return;
    }

    final double target =
        _messageScrollController.position.maxScrollExtent;

    if (animated) {
      _messageScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _messageScrollController.jumpTo(target);
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _scrollToBottom(animated: false);

      for (final int delay in <int>[70, 170]) {
        unawaited(
          Future<void>.delayed(
            Duration(milliseconds: delay),
            () {
              if (!mounted) {
                return;
              }
              _scrollToBottom();
            },
          ),
        );
      }
    });
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _tavernBackground,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: false,
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
      ),
    );
  }


  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width = constraints.maxWidth;
        final double screenHeight = MediaQuery.sizeOf(context).height;
        final double systemTop = MediaQuery.paddingOf(context).top;
        final bool shortScreen = screenHeight < 690;

        // Le visuel principal garde ses proportions : on ajoute seulement
        // quelques pixels en dessous pour que la présence ait enfin sa place.
        final double artHeight = (width * (260 / 971))
            .clamp(shortScreen ? 94.0 : 100.0, shortScreen ? 108.0 : 118.0)
            .toDouble();
        final double presenceBandHeight = width < 340 ? 17.0 : 20.0;
        final double height = artHeight + presenceBandHeight;

        final double dpr = MediaQuery.devicePixelRatioOf(context);
        final int cacheWidth = (width * dpr)
            .round()
            .clamp(420, 1180)
            .toInt();

        // Le Communicateur global occupe 48 x 42 à systemTop + 7 / right 8
        // (voir global_communicator_alert.dart). La flèche et la palette
        // utilisent exactement le même axe vertical.
        final double phoneTop = systemTop + 7.0;
        const double phoneHeight = 42.0;
        const double phoneWidth = 48.0;
        const double phoneRight = 8.0;
        final double phoneReserve = phoneWidth + phoneRight;

        // Même bouton Hall que Compagnie, Terminal XP et Communicateur.
        // Sa zone visuelle reste identique partout : 44 × 40.
        const double hallButtonWidth = 44.0;
        const double hallButtonHeight = 40.0;
        final double backLeft = width < 340 ? 7.0 : 10.0;
        final double backTop =
            phoneTop + ((phoneHeight - hallButtonHeight) / 2);

        final double paletteSize = width < 340 ? 28.0 : 30.0;
        final double paletteTop = phoneTop + ((phoneHeight - paletteSize) / 2);
        final double paletteRight = phoneRight + phoneWidth + 7.0;

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xff160d08),
                        Color(0xff21140c),
                        Color(0xff130b07),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: artHeight,
                child: Image.asset(
                  _tavernHeaderAsset,
                  fit: BoxFit.fill,
                  cacheWidth: cacheWidth,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),

              // Grand espace directement ouvert depuis le Hall : on utilise
              // l'icône Hall, jamais la flèche réservée aux retours internes.
              // Le bouton opaque recouvre proprement l'ancienne plaque du décor.
              Positioned(
                left: backLeft,
                top: backTop,
                width: hallButtonWidth,
                height: hallButtonHeight,
                child: HallHomeButton(
                  width: hallButtonWidth,
                  height: hallButtonHeight,
                ),
              ),

              if (_isProjectXpAdmin)
                Positioned(
                  left: backLeft + hallButtonWidth + 2.0,
                  top: backTop + ((hallButtonHeight - 28) / 2),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<String>(
                      tooltip: 'Administration Project XP',
                      color: const Color(0xff21150e),
                      enabled: !_resettingTavern,
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: _resettingTavern
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _tavernGold,
                              ),
                            )
                          : const Icon(
                              Icons.admin_panel_settings_outlined,
                              color: _tavernGold,
                            ),
                      onSelected: (String value) {
                        if (value == 'reset_tavern') {
                          _confirmResetTavern();
                        }
                      },
                      itemBuilder: (BuildContext context) {
                        return const [
                          PopupMenuItem<String>(
                            value: 'reset_tavern',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_sweep_outlined,
                                  color: Colors.redAccent,
                                ),
                                SizedBox(width: 10),
                                Text('Réinitialiser le chat'),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
                ),

              // Palette personnelle juste à côté du téléphone. Le téléphone
              // lui-même n'est pas déplacé et reste global à toute l'app.
              Positioned(
                right: paletteRight,
                top: paletteTop,
                width: paletteSize,
                height: paletteSize,
                child: _buildHeaderChatColorButton(),
              ),

              // La présence possède une vraie continuation de bois :
              // aucune barre noire rapportée sous le titre.
              Positioned(
                left: 0,
                right: 0,
                top: artHeight,
                height: presenceBandHeight,
                child: IgnorePointer(
                  child: Image.asset(
                    _tavernTabsBackgroundAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: artHeight,
                height: presenceBandHeight,
                child: Center(
                  child: _buildPresenceUnderTitle(),
                ),
              ),

              // Espace réservé au Communicateur global.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(width: phoneReserve),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderChatColorButton() {
    final Color currentAccent = _currentChatAccent;

    return Tooltip(
      message: 'Changer ma couleur de chat',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _savingChatColor ? null : _openChatColorPicker,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(
                color: currentAccent.withValues(alpha: 0.92),
                width: 1.6,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: _savingChatColor
                ? Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: currentAccent,
                    ),
                  )
                : Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: currentAccent,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresenceUnderTitle() {
    return StreamBuilder<int>(
      stream: OnlinePresenceService.instance.onlineCountStream,
      initialData: OnlinePresenceService.instance.currentCount,
      builder: (
        BuildContext context,
        AsyncSnapshot<int> snapshot,
      ) {
        final int count = snapshot.data ?? 0;
        final bool compact = MediaQuery.sizeOf(context).width < 340;
        final String label = count == 1
            ? '$count aventurier en ligne'
            : '$count aventuriers en ligne';

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Row(
            key: ValueKey<int>(count),
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 5.0 : 6.0,
                height: compact ? 5.0 : 6.0,
                decoration: const BoxDecoration(
                  color: Color(0xff38d66b),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x5538d66b),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 4 : 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  color: const Color(0xffd8c09a),
                  fontSize: compact ? 7.6 : 8.4,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08,
                  height: 1,
                  shadows: const [
                    Shadow(
                      color: Color(0xdd000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 44,
                color: Colors.orangeAccent,
              ),
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loadingChannels = true;
                    _errorMessage = null;
                  });
                  _loadChannels();
                },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_channels.isEmpty) {
      return const Center(
        child: Text('Aucun channel disponible.'),
      );
    }

    return Container(
      color: _tavernBackground,
      child: Column(
        children: [
          _buildChannelSelector(),
          Expanded(
            child: PageView.builder(
              controller: _sectionPageController,
              itemCount: _tavernSections.length,
              physics: const PageScrollPhysics(),
              onPageChanged: _handleSectionPageChanged,
              itemBuilder: (
                BuildContext context,
                int index,
              ) {
                return _buildSectionPage(index);
              },
            ),
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
        final double width = constraints.maxWidth;
        final double selectorHeight = (width * 0.155)
            .clamp(54.0, 66.0)
            .toDouble();
        // Environ 2,7 onglets visibles sur un téléphone standard : on comprend
        // immédiatement que le bandeau se fait glisser, sans grands espaces.
        final double itemWidth = (width * 0.34)
            .clamp(112.0, 166.0)
            .toDouble();
        final double gap = width < 340 ? 0.5 : 1.5;

        return SizedBox(
          height: selectorHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _tavernTabsBackgroundAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x3d090604),
                  border: Border(
                    bottom: BorderSide(
                      color: _tavernGoldDeep.withValues(alpha: 0.62),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
              ListView.separated(
                controller: _sectionTabScrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: width < 340 ? 2 : 3,
                  vertical: 3,
                ),
                itemCount: _tavernSections.length,
                separatorBuilder: (_, _) => SizedBox(width: gap),
                itemBuilder: (BuildContext context, int index) {
                  return SizedBox(
                    key: _sectionTabKeys[index],
                    width: itemWidth,
                    child: _buildChannelTab(index: index),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelTab({
    required int index,
  }) {
    final Map<String, String> section = _tavernSections[index];
    final bool selected = index == _selectedSectionIndex;
    final String label = section['label'] ?? '';
    final String displayLabel = label == 'Quêtes & Aventures'
        ? 'Quêtes &\nAventures'
        : label;
    final String icon = section['icon'] ?? '';

    return AnimatedScale(
      scale: selected ? 1.0 : 0.982,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectSectionFromTab(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                selected ? _tavernTabSelectedAsset : _tavernTabIdleAsset,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 5,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      icon,
                      style: TextStyle(
                        fontSize: label.length > 13 ? 16 : 18,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        displayLabel,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xffffd878)
                              : const Color(0xffeee2d5),
                          fontSize: label == 'Quêtes & Aventures'
                              ? 9.35
                              : (label.length > 14 ? 9.8 : 10.8),
                          height: label == 'Quêtes & Aventures' ? 0.98 : 1.02,
                          fontWeight: FontWeight.w800,
                          shadows: const [
                            Shadow(
                              color: Color(0xcc000000),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
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

  void _selectSectionFromTab(int index) {
    if (index < 0 || index >= _tavernSections.length) {
      return;
    }

    _activateSection(index);

    if (_sectionPageController.hasClients) {
      _sectionPageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleSectionPageChanged(int index) {
    _activateSection(index);
  }

  void _activateSection(int index) {
    if (index < 0 || index >= _tavernSections.length) {
      return;
    }

    if (_selectedSectionIndex != index) {
      setState(() {
        _selectedSectionIndex = index;
      });
    }

    final String slug = _tavernSections[index]['slug'] ?? '';
    final Map<String, dynamic>? channel = _channelForSection(slug);
    if (channel != null) {
      _selectChannel(channel);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureSectionTabVisible(index);
    });
  }

  void _ensureSectionTabVisible(int index) {
    if (!mounted || index < 0 || index >= _sectionTabKeys.length) {
      return;
    }

    final BuildContext? tabContext = _sectionTabKeys[index].currentContext;
    if (tabContext == null) {
      return;
    }

    Scrollable.ensureVisible(
      tabContext,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  Map<String, dynamic>? _channelForSection(String slug) {
    for (final Map<String, dynamic> channel in _channels) {
      final String channelSlug =
          channel['slug']?.toString().toLowerCase() ?? '';
      final String channelName =
          channel['name']?.toString().toLowerCase() ?? '';

      if (slug == 'comptoir' && channelSlug == 'comptoir') {
        return channel;
      }
      if (slug == 'quetes' &&
          (channelSlug.contains('quete') ||
              channelName.contains('quête') ||
              channelName.contains('quete'))) {
        return channel;
      }
      if (slug == 'marche' &&
          (channelSlug.contains('marche') ||
              channelName.contains('marché') ||
              channelName.contains('marche'))) {
        return channel;
      }
      if (slug == 'des_jeux' &&
          (channelSlug.contains('des') ||
              channelSlug.contains('jeu') ||
              channelName.contains('dés') ||
              channelName.contains('jeux'))) {
        return channel;
      }
      if (slug == 'hauts_faits' &&
          (channelSlug.contains('haut') ||
              channelSlug.contains('fait') ||
              channelName.contains('haut') ||
              channelName.contains('fait'))) {
        return channel;
      }
    }

    return null;
  }

  Widget _buildSectionPage(int index) {
    final Map<String, String> section = _tavernSections[index];
    final String slug = section['slug'] ?? '';

    if (slug == 'comptoir') {
      final Map<String, dynamic>? comptoir = _channelForSection('comptoir');
      if (comptoir == null) {
        return const Center(
          child: Text('Le Comptoir est indisponible.'),
        );
      }
      return _buildComptoir(comptoir);
    }

    final Map<String, dynamic>? channel = _channelForSection(slug);
    final Map<String, dynamic> displayChannel = channel ??
        <String, dynamic>{
          'icon': section['icon'] ?? '✦',
          'name': section['title'] ?? section['label'] ?? '',
          'description': section['description'] ?? '',
        };

    return _buildFutureChannel(displayChannel);
  }

  Widget _buildComptoir(
    Map<String, dynamic> channel,
  ) {
    final String channelId = channel['id']?.toString() ?? '';

    if (channelId.isEmpty) {
      return const Center(
        child: Text('Channel invalide.'),
      );
    }

    final Stream<List<Map<String, dynamic>>>? messageStream = _messageStream;

    if (messageStream == null) {
      return const Center(
        child: Text('Flux du channel indisponible.'),
      );
    }

    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width = constraints.maxWidth;
        final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        final double composerHeight = _composerHeightForWidth(width);

        if ((keyboardInset - _lastKeyboardInset).abs() > 1) {
          _lastKeyboardInset = keyboardInset;
          if (keyboardInset > 0) {
            _scheduleScrollToBottom();
          }
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Le décor reste plein écran de la Taverne. Il ne change plus de
            // taille quand Android ouvre le clavier.
            StreamBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(channelId),
              stream: messageStream,
              builder: (
                BuildContext context,
                AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
              ) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _tavernGold),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Impossible de charger les messages.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final List<Map<String, dynamic>> messages =
                    snapshot.data ?? <Map<String, dynamic>>[];

                final String pendingContent =
                    _pendingMessageContent?.trim() ?? '';
                final bool hasPendingMessage = pendingContent.isNotEmpty &&
                    _pendingMessageChannelId == channelId;
                final int renderedItemCount =
                    messages.length + (hasPendingMessage ? 1 : 0);

                if (renderedItemCount != _lastAutoScrollItemCount) {
                  _lastAutoScrollItemCount = renderedItemCount;
                  if (renderedItemCount > 0) {
                    _scheduleScrollToBottom();
                  }
                }

                return _buildChatStage(
                  messages: messages,
                  hasPendingMessage: hasPendingMessage,
                  pendingContent: pendingContent,
                  obscuredBottom: keyboardInset + composerHeight + 12,
                );
              },
            ),

            // Seule la barre de saisie remonte au-dessus du clavier.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: keyboardInset,
              height: composerHeight,
              child: _buildMessageComposer(),
            ),
          ],
        );
      },
    );
  }

  double _composerHeightForWidth(double width) {
    return (width * (159 / 971))
        .clamp(54.0, 68.0)
        .toDouble();
  }

  Widget _buildDiscussionHeader() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width = constraints.maxWidth;
        final double height = (width * 0.072)
            .clamp(24.0, 30.0)
            .toDouble();
        return SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.only(
                        left: 12,
                        right: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            _tavernGold.withValues(
                              alpha: 0.45,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 6,
                    ),
                    child: Text(
                      '✦',
                      style: TextStyle(
                        color: _tavernGold.withValues(
                          alpha: 0.92,
                        ),
                        fontSize: width < 340 ? 8 : 9,
                      ),
                    ),
                  ),
                  Text(
                    'DISCUSSION GÉNÉRALE',
                    maxLines: 1,
                    style: TextStyle(
                      color: const Color(0xffcaa0f5),
                      fontSize: width < 340 ? 8.9 : 9.9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.18,
                      shadows: const [
                        Shadow(
                          color: Color(0xaa000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                    ),
                    child: Text(
                      '✦',
                      style: TextStyle(
                        color: _tavernGold.withValues(
                          alpha: 0.92,
                        ),
                        fontSize: width < 340 ? 8 : 9,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.only(
                        left: 2,
                        right: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _tavernGold.withValues(
                              alpha: 0.45,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
    required double obscuredBottom,
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
            (width * 0.196)
                .clamp(
                  46.0,
                  112.0,
                )
                .toDouble();

        if (width < 285 ||
            height < 250) {
          shelfWidth = 0;
        } else if (width < 330) {
          shelfWidth =
              (width * 0.17)
                  .clamp(
                    36.0,
                    48.0,
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
                        1.2)
                    .round()
                    .clamp(
                      80,
                      220,
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
                  ? 8
                  : 12,
              width < 350 ? 36 : 40,
              width < 350
                  ? 8
                  : 12,
              obscuredBottom.clamp(68.0, 520.0).toDouble(),
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
          fit:
              StackFit.expand,
          children: [
            Positioned.fill(
              child: Image.asset(
                _tavernCenterWoodAsset,
                fit:
                    BoxFit.cover,
                alignment:
                    Alignment.topCenter,
                filterQuality:
                    FilterQuality.medium,
              ),
            ),
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
                      Color(0x14080504),
                      Color(0x1e0a0705),
                      Color(0x240a0705),
                      Color(0x12080504),
                    ],
                    stops: [
                      0,
                      0.22,
                      0.78,
                      1,
                    ],
                  ),
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
                    child:
                        Image.asset(
                      _tavernShelfLeftAsset,
                      fit:
                          BoxFit.cover,
                      alignment:
                          Alignment.topCenter,
                      cacheWidth:
                          shelfCacheWidth,
                      filterQuality:
                          FilterQuality.high,
                      gaplessPlayback:
                          true,
                    ),
                  ),
                Expanded(
                  child: Container(
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0x140a0705,
                      ),
                      border:
                          Border(
                        left:
                            BorderSide(
                          color:
                              _tavernGoldDeep
                                  .withValues(
                            alpha:
                                0.66,
                          ),
                          width:
                              1.35,
                        ),
                        right:
                            BorderSide(
                          color:
                              _tavernGoldDeep
                                  .withValues(
                            alpha:
                                0.66,
                          ),
                          width:
                              1.35,
                        ),
                        top:
                            BorderSide(
                          color:
                              _tavernGoldDeep
                                  .withValues(
                            alpha:
                                0.50,
                          ),
                          width:
                              1.05,
                        ),
                        bottom:
                            BorderSide(
                          color:
                              _tavernGoldDeep
                                  .withValues(
                            alpha:
                                0.46,
                          ),
                          width:
                              1.05,
                        ),
                      ),
                    ),
                    child:
                        center,
                  ),
                ),
                if (shelfWidth > 0)
                  SizedBox(
                    width:
                        shelfWidth,
                    child:
                        Image.asset(
                      _tavernShelfRightAsset,
                      fit:
                          BoxFit.cover,
                      alignment:
                          Alignment.topCenter,
                      cacheWidth:
                          shelfCacheWidth,
                      filterQuality:
                          FilterQuality.high,
                      gaplessPlayback:
                          true,
                    ),
                  ),
              ],
            ),
            Positioned(
              left: shelfWidth,
              right: shelfWidth,
              top: 4,
              child: _buildDiscussionHeader(),
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
            width < 230 ||
            height < 390;

        final double maxCardWidth =
            (width * 0.72)
                .clamp(
                  170.0,
                  250.0,
                )
                .toDouble();

        final double beerSize =
            compact
                ? 42
                : 48;

        return Center(
          child:
              SingleChildScrollView(
            padding:
                EdgeInsets.symmetric(
              horizontal:
                  compact
                      ? 6
                      : 10,
              vertical:
                  compact
                      ? 8
                      : 12,
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
                      ? 12
                      : 15,
                  compact
                      ? 12
                      : 15,
                  compact
                      ? 12
                      : 15,
                  compact
                      ? 11
                      : 14,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xc824150e,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                  border:
                      Border.all(
                    color:
                        const Color(
                      0xff714625,
                    ),
                  ),
                  boxShadow:
                      const [
                    BoxShadow(
                      color:
                          Color(
                        0x99000000,
                      ),
                      blurRadius:
                          18,
                      offset:
                          Offset(
                        0,
                        8,
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
                          beerSize + 18,
                      height:
                          beerSize + 18,
                      alignment:
                          Alignment.center,
                      decoration:
                          BoxDecoration(
                        shape:
                            BoxShape.circle,
                        color:
                            const Color(
                          0x40150c08,
                        ),
                        border:
                            Border.all(
                          color:
                              const Color(
                            0xffa66e32,
                          ),
                        ),
                      ),
                      child: Text(
                        '🍺',
                        style:
                            TextStyle(
                          fontSize:
                              beerSize,
                        ),
                      ),
                    ),
                    SizedBox(
                      height:
                          compact
                              ? 10
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
                            1.18,
                      ),
                    ),
                    const SizedBox(
                      height: 7,
                    ),
                    Text(
                      'Sois le premier aventurier à parler.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            Colors.white60,
                        fontSize:
                            compact
                                ? 11
                                : 12,
                        height:
                            1.35,
                      ),
                    ),
                    const SizedBox(
                      height: 11,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child:
                              Divider(
                            color:
                                _tavernGold
                                    .withValues(
                              alpha:
                                  0.25,
                            ),
                          ),
                        ),
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(
                            horizontal:
                                8,
                          ),
                          child: Text(
                            '✦',
                            style:
                                TextStyle(
                              color:
                                  _tavernGold,
                              fontSize:
                                  11,
                            ),
                          ),
                        ),
                        Expanded(
                          child:
                              Divider(
                            color:
                                _tavernGold
                                    .withValues(
                              alpha:
                                  0.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      'Ici, chacun a une histoire à partager.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        color:
                            const Color(
                          0xffc99a6f,
                        ),
                        fontSize:
                            compact
                                ? 10
                                : 11,
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
    final String messageId =
        message['id']?.toString().trim() ?? '';
    final String authorId =
        message['author_id']?.toString() ?? '';
    final Map<String, dynamic>? profile =
        _asStringDynamicMap(message['author_profile']);
    final String displayName =
        profile?['display_name']?.toString().trim() ?? '';
    final String authorName = displayName.isNotEmpty
        ? displayName
        : _fallbackAuthorName(authorId);
    final String content =
        message['content']?.toString() ?? '';
    final String createdAt = _formatMessageTime(
      message['created_at']?.toString(),
    );
    final Color accent = _messageAccent(
      profile,
      authorId,
    );
    final Color bubbleColor = Color.lerp(
          const Color(0xe817100c),
          accent,
          0.026,
        ) ??
        const Color(0xe817100c);

    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double width = constraints.maxWidth;
        final bool compact = width < 245;
        final double avatarSize = (width * 0.145)
            .clamp(36.0, 50.0)
            .toDouble();
        final double gap = compact ? 6 : 8;
        final double horizontalPadding =
            (compact ? 9 : 12) * 2;

        final double availableBubbleWidth =
            math.max(
          96,
          math.min(
            560,
            width - avatarSize - gap,
          ),
        );

        final TextStyle authorStyle =
            TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 11.5 : 13,
        );

        final TextStyle timeStyle =
            TextStyle(
          color: const Color(0xffd7cbbf)
              .withValues(alpha: 0.68),
          fontSize: compact ? 8.8 : 9.8,
        );

        final TextStyle contentStyle =
            TextStyle(
          color: const Color(0xfff5eee6),
          fontSize: compact ? 12.5 : 13.5,
          height: 1.34,
        );

        double singleLineWidth(
          String value,
          TextStyle style,
          double maxWidth,
        ) {
          if (value.isEmpty) {
            return 0;
          }

          final TextPainter painter =
              TextPainter(
            text: TextSpan(
              text: value,
              style: style,
            ),
            maxLines: 1,
            textDirection:
                Directionality.of(context),
          )..layout(
              maxWidth: math.max(
                1,
                maxWidth,
              ),
            );

          return painter.width;
        }

        final double innerMaxWidth =
            math.max(
          24,
          availableBubbleWidth -
              horizontalPadding,
        );

        final double authorWidth =
            math.min(
          compact ? 110 : 170,
          singleLineWidth(
            authorName,
            authorStyle,
            compact ? 110 : 170,
          ),
        );

        final double timeWidth =
            singleLineWidth(
          createdAt,
          timeStyle,
          60,
        );

        final double adminWidth =
            _isProjectXpAdmin &&
                    messageId.isNotEmpty
                ? 26
                : 0;

        final double headerWidth =
            authorWidth +
                (createdAt.isEmpty
                    ? 0
                    : 8 + timeWidth) +
                adminWidth;

        final double contentWidth =
            singleLineWidth(
          content,
          contentStyle,
          innerMaxWidth,
        );

        final double minimumBubbleWidth =
            math.min(
          availableBubbleWidth,
          compact ? 132 : 156,
        );

        final double bubbleWidth =
            math.max(
          minimumBubbleWidth,
          math.min(
            availableBubbleWidth,
            math.max(
                  headerWidth,
                  contentWidth,
                ) +
                horizontalPadding,
          ),
        );

        final bool deleting =
            messageId.isNotEmpty &&
                _deletingMessageIds.contains(
                  messageId,
                );

        return Align(
          alignment: Alignment.centerLeft,
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
                      authorId: authorId,
                      profile: profile,
                    );
                  },
                  child: _buildAuthorAvatar(
                    profile: profile,
                    authorId: authorId,
                    displayName: authorName,
                    size: avatarSize,
                    accent: accent,
                  ),
                ),
                SizedBox(width: gap),
                Flexible(
                  child: Align(
                    alignment:
                        Alignment.centerLeft,
                    child: SizedBox(
                      width: bubbleWidth,
                      child: Container(
                        padding:
                            EdgeInsets.fromLTRB(
                          compact ? 9 : 12,
                          compact ? 7 : 9,
                          compact ? 9 : 12,
                          compact ? 8 : 10,
                        ),
                        decoration:
                            BoxDecoration(
                          color: bubbleColor,
                          borderRadius:
                              BorderRadius.circular(
                            compact ? 12 : 14,
                          ),
                          border:
                              Border.all(
                            color: accent
                                .withValues(
                              alpha: 0.34,
                            ),
                            width: 0.68,
                          ),
                          boxShadow: [
                            const BoxShadow(
                              color:
                                  Color(
                                0x48000000,
                              ),
                              blurRadius: 7,
                              offset:
                                  Offset(0, 3),
                            ),
                            BoxShadow(
                              color: accent
                                  .withValues(
                                alpha:
                                    0.018,
                              ),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child:
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
                                    child: Text(
                                      authorName,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style:
                                          authorStyle,
                                    ),
                                  ),
                                ),
                                if (createdAt
                                    .isNotEmpty) ...[
                                  const SizedBox(
                                    width: 8,
                                  ),
                                  Text(
                                    createdAt,
                                    style:
                                        timeStyle,
                                  ),
                                ],
                                if (_isProjectXpAdmin &&
                                    messageId
                                        .isNotEmpty) ...[
                                  const SizedBox(
                                    width: 3,
                                  ),
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child:
                                        IconButton(
                                      tooltip:
                                          'Supprimer ce message',
                                      padding:
                                          EdgeInsets.zero,
                                      visualDensity:
                                          VisualDensity.compact,
                                      onPressed:
                                          deleting
                                              ? null
                                              : () {
                                                  _confirmDeleteTavernMessage(
                                                    message,
                                                  );
                                                },
                                      icon:
                                          deleting
                                              ? const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth:
                                                        1.5,
                                                    color:
                                                        Colors.redAccent,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons
                                                      .delete_outline_rounded,
                                                  size:
                                                      15,
                                                  color:
                                                      Color(
                                                    0xffd87474,
                                                  ),
                                                ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(
                              height: 4,
                            ),
                            Text(
                              content,
                              style:
                                  contentStyle,
                            ),
                          ],
                        ),
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

  Color _messageAccent(
    Map<String, dynamic>? profile,
    String authorId,
  ) {
    final String currentUserId =
        SupabaseService.currentUser?.id ?? '';

    if (authorId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        authorId == currentUserId) {
      return _currentChatAccent;
    }

    const List<String> directKeys = <String>[
      'message_color',
      'chat_color',
      'accent_color',
      'profile_color',
      'color',
    ];

    if (profile != null) {
      for (final String key in directKeys) {
        final Color? parsed = _parseProfileColor(profile[key]);
        if (parsed != null) {
          return parsed;
        }
      }

      for (final String nestedKey in <String>[
        'preferences',
        'settings',
        'metadata',
        'public_profile_data',
      ]) {
        final Map<String, dynamic>? nested =
            _asStringDynamicMap(profile[nestedKey]);
        if (nested == null) {
          continue;
        }
        for (final String key in directKeys) {
          final Color? parsed = _parseProfileColor(nested[key]);
          if (parsed != null) {
            return parsed;
          }
        }
      }
    }

    return _authorAccent(authorId);
  }

  Color? _parseProfileColor(dynamic raw) {
    if (raw == null) {
      return null;
    }

    if (raw is int) {
      final int value = raw <= 0xFFFFFF ? (0xFF000000 | raw) : raw;
      return Color(value);
    }

    String value = raw.toString().trim();
    if (value.isEmpty) {
      return null;
    }

    value = value
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');

    if (value.length == 6) {
      value = 'FF$value';
    }

    if (value.length != 8) {
      return null;
    }

    final int? parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(parsed);
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
        final double width = constraints.maxWidth;
        final double height = _composerHeightForWidth(width);

        final double plusLeft = width * (25 / 971);
        final double plusWidth = width * (125 / 971);
        final double fieldLeft = width * (160 / 971);
        final double fieldRight = width * (296 / 971);
        final double emojiLeft = width * (698 / 971);
        final double emojiWidth = width * (108 / 971);
        final double sendLeft = width * (808 / 971);
        final double sendWidth = width * (138 / 971);

        return SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _tavernComposerAsset,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
              // Zone intérieure exacte du cadre rasterisé (asset 971x159).
              // Le TextField remplit cette zone et centre lui-même le texte :
              // plus aucun décalage manuel de baseline.
              Positioned(
                left: fieldLeft,
                right: fieldRight,
                top: height * (36 / 159),
                bottom: height * (35 / 159),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _messageController,
                  child: TextField(
                    controller: _messageController,
                    minLines: null,
                    maxLines: null,
                    expands: true,
                    maxLength: 2000,
                    textAlignVertical: TextAlignVertical.center,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    scrollPadding: const EdgeInsets.only(bottom: 110),
                    style: TextStyle(
                      color: const Color(0xfff3ece4),
                      fontSize: width < 330 ? 12.2 : 13.2,
                      height: 1.0,
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onTap: _scheduleScrollToBottom,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                  builder: (
                    BuildContext context,
                    TextEditingValue value,
                    Widget? child,
                  ) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (value.text.isEmpty)
                          Align(
                            alignment: Alignment.center,
                            child: IgnorePointer(
                              child: Text(
                                'Écrire un message...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: width < 330 ? 12.2 : 13.2,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ?child,
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                left: plusLeft,
                top: 0,
                bottom: 0,
                width: plusWidth,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          duration: Duration(milliseconds: 1100),
                          content: Text(
                            'Les pièces jointes arriveront bientôt.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: emojiLeft,
                top: 0,
                bottom: 0,
                width: emojiWidth,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          duration: Duration(milliseconds: 900),
                          content: Text('Les réactions arrivent bientôt.'),
                        ),
                      );
                    },
                    child: const Center(
                      child: Icon(
                        Icons.sentiment_satisfied_alt_rounded,
                        color: Color(0xffffc75d),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: sendLeft,
                top: 0,
                bottom: 0,
                width: sendWidth,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _sendingMessage ? null : _sendMessage,
                    child: Center(
                      child: _sendingMessage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Color(0xffffcf72),
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        color: Color(
          0xff17100c,
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
              fontSize: 25,
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  name,
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
                if (description.isNotEmpty) ...[
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    description,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
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


  Widget _buildFutureChannel(
    Map<String, dynamic> channel,
  ) {
    final String icon = channel['icon']?.toString() ?? '✦';
    final String name = channel['name']?.toString() ?? '';
    final String description = channel['description']?.toString() ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _tavernSimpleBackgroundAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x450b0705),
                Color(0x8a0b0705),
                Color(0xa60b0705),
              ],
            ),
          ),
        ),
        Column(
          children: [
            _buildChannelTitle(channel),
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 330),
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                  decoration: BoxDecoration(
                    color: const Color(0xd91b110c),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xff7f5329),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x88000000),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        icon,
                        style: const TextStyle(fontSize: 50),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xffffd27a),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'Contenu à venir…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xffc58aff),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
