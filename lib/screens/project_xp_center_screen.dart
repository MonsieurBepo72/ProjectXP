import 'package:flutter/material.dart';

import 'computer_screen.dart';

/// Compatibilité avec la V1.7.0.
///
/// Le Centre Project XP n'est plus une destination séparée du Hall :
/// les réglages vivent désormais dans le Terminal XP, derrière l'engrenage
/// du Portail des Aventuriers.
@Deprecated('Utiliser ComputerScreen / Terminal XP.')
class ProjectXpCenterScreen extends StatelessWidget {
  const ProjectXpCenterScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const ComputerScreen();
  }
}
