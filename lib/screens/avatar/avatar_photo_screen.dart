import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/avatar_model.dart';
import '../../services/auth_service.dart';
import '../../services/avatar_generation_service.dart';
import 'avatar_preview_screen.dart';

class AvatarPhotoScreen
    extends StatefulWidget {
  const AvatarPhotoScreen({super.key});

  @override
  State<AvatarPhotoScreen> createState() =>
      _AvatarPhotoScreenState();
}

class _AvatarPhotoScreenState
    extends State<AvatarPhotoScreen> {
  final ImagePicker _picker =
      ImagePicker();

  XFile? _selectedPhoto;

  bool _generating = false;

  Future<void> _pickPhoto(
    ImageSource source,
  ) async {
    try {
      final XFile? photo =
          await _picker.pickImage(
        source: source,
        imageQuality: 90,
        preferredCameraDevice:
            CameraDevice.front,
      );

      if (photo == null || !mounted) {
        return;
      }

      setState(() {
        _selectedPhoto = photo;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de récupérer la photo : $error',
          ),
        ),
      );
    }
  }

  void _removePhoto() {
    if (_generating) {
      return;
    }

    setState(() {
      _selectedPhoto = null;
    });
  }

  Future<void> _generateAvatar() async {
    final XFile? selectedPhoto =
        _selectedPhoto;

    if (selectedPhoto == null ||
        _generating) {
      return;
    }

    setState(() {
      _generating = true;
    });

    try {
      final String? userId =
          await AuthService
              .getCurrentUserId();

      if (userId == null) {
        throw Exception(
          'Impossible de retrouver ton compte.',
        );
      }

      final String generatedPath =
          await AvatarGenerationService
              .generateFromPhoto(
        selectedPhoto.path,
      );

      if (!mounted) {
        return;
      }

      final DateTime now =
          DateTime.now();

      final AvatarModel avatar =
          AvatarModel(
        userId: userId,
        creationMode:
            AvatarCreationMode.photo,
        generatedImagePath:
            generatedPath,
        createdAt: now,
        updatedAt: now,
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              AvatarPreviewScreen(
                avatar: avatar,
                saveOnValidate: true,
              ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            _cleanError(error),
          ),
          duration:
              const Duration(
            seconds: 5,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
        });
      }
    }
  }

  String _cleanError(
    Object error,
  ) {
    final String message =
        error.toString();

    if (message.startsWith(
      'Exception: ',
    )) {
      return message.substring(11);
    }

    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xff160e09),
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        foregroundColor:
            const Color(0xffffc857),
        elevation: 0,
        title: const Text(
          'Avatar depuis une photo',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            15,
            24,
            25,
          ),
          child: Column(
            children: [
              const Text(
                'MONTRE-NOUS TON VISAGE',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  color:
                      Color(0xffffc857),
                  fontSize: 22,
                  fontWeight:
                      FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Choisis une photo nette et bien éclairée. '
                'Elle servira plus tard de référence pour créer ton aventurier.',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xff21150e,
                    ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      22,
                    ),
                    border:
                        Border.all(
                      color:
                          const Color(
                        0xffffc857,
                      ),
                      width: 2,
                    ),
                    boxShadow:
                        const [
                      BoxShadow(
                        color:
                            Colors.black54,
                        blurRadius: 16,
                        offset:
                            Offset(
                          0,
                          7,
                        ),
                      ),
                    ],
                  ),
                  clipBehavior:
                      Clip.antiAlias,
                  child:
                      _selectedPhoto ==
                              null
                          ? _buildEmptyPhoto()
                          : _buildSelectedPhoto(),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child:
                        OutlinedButton
                            .icon(
                      onPressed:
                          _generating
                              ? null
                              : () {
                                  _pickPhoto(
                                    ImageSource
                                        .camera,
                                  );
                                },
                      icon:
                          const Icon(
                        Icons
                            .camera_alt,
                      ),
                      label:
                          const Text(
                        'CAMÉRA',
                      ),
                      style:
                          OutlinedButton
                              .styleFrom(
                        foregroundColor:
                            const Color(
                          0xffffc857,
                        ),
                        side:
                            const BorderSide(
                          color:
                              Color(
                            0xffffc857,
                          ),
                        ),
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child:
                        OutlinedButton
                            .icon(
                      onPressed:
                          _generating
                              ? null
                              : () {
                                  _pickPhoto(
                                    ImageSource
                                        .gallery,
                                  );
                                },
                      icon:
                          const Icon(
                        Icons
                            .photo_library,
                      ),
                      label:
                          const Text(
                        'GALERIE',
                      ),
                      style:
                          OutlinedButton
                              .styleFrom(
                        foregroundColor:
                            const Color(
                          0xffffc857,
                        ),
                        side:
                            const BorderSide(
                          color:
                              Color(
                            0xffffc857,
                          ),
                        ),
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (_selectedPhoto !=
                  null) ...[
                const SizedBox(height: 5),

                TextButton.icon(
                  onPressed:
                      _generating
                          ? null
                          : _removePhoto,
                  icon:
                      const Icon(
                    Icons
                        .delete_outline,
                  ),
                  label:
                      const Text(
                    'RETIRER LA PHOTO',
                  ),
                  style:
                      TextButton.styleFrom(
                    foregroundColor:
                        Colors.white54,
                  ),
                ),
              ],

              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets
                        .all(
                  12,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xff2b1b12,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    12,
                  ),
                  border:
                      Border.all(
                    color:
                        Colors.white12,
                  ),
                ),
                child:
                    const Row(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Icon(
                      Icons
                          .construction,
                      color:
                          Color(
                        0xffffc857,
                      ),
                      size: 20,
                    ),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'MODE DEV GRATUIT : aucune IA réelle n’est utilisée. '
                        'Project XP affichera simplement ta photo comme résultat '
                        'afin de tester le parcours complet.',
                        style:
                            TextStyle(
                          color:
                              Colors.white60,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 56,
                child:
                    ElevatedButton
                        .icon(
                  onPressed:
                      _selectedPhoto ==
                                  null ||
                              _generating
                          ? null
                          : _generateAvatar,
                  icon:
                      _generating
                          ? const SizedBox(
                              width: 21,
                              height: 21,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    3,
                              ),
                            )
                          : const Icon(
                              Icons
                                  .auto_awesome,
                            ),
                  label: Text(
                    _generating
                        ? 'CRÉATION EN COURS...'
                        : 'GÉNÉRER MON AVATAR',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      letterSpacing:
                          0.7,
                    ),
                  ),
                  style:
                      ElevatedButton
                          .styleFrom(
                    backgroundColor:
                        const Color(
                      0xffffc857,
                    ),
                    foregroundColor:
                        const Color(
                      0xff21150e,
                    ),
                    disabledBackgroundColor:
                        const Color(
                      0xff5c4a30,
                    ),
                    disabledForegroundColor:
                        Colors.white38,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPhoto() {
    return const Center(
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            Icons.person_outline,
            color: Colors.white24,
            size: 110,
          ),

          SizedBox(height: 15),

          Text(
            'Aucune photo sélectionnée',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 15,
            ),
          ),

          SizedBox(height: 5),

          Text(
            'Caméra ou galerie',
            style: TextStyle(
              color: Colors.white30,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPhoto() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(
            _selectedPhoto!.path,
          ),
          fit: BoxFit.cover,
        ),

        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding:
                const EdgeInsets
                    .symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration:
                BoxDecoration(
              color:
                  const Color(
                0xdd21150e,
              ),
              borderRadius:
                  BorderRadius
                      .circular(
                20,
              ),
              border:
                  Border.all(
                color:
                    const Color(
                  0xffffc857,
                ),
              ),
            ),
            child:
                const Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  Icons.check,
                  color:
                      Color(
                    0xffffc857,
                  ),
                  size: 16,
                ),

                SizedBox(width: 5),

                Text(
                  'PHOTO PRÊTE',
                  style:
                      TextStyle(
                    color:
                        Color(
                      0xffffc857,
                    ),
                    fontSize: 10,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}