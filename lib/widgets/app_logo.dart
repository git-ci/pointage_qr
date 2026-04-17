import 'package:flutter/material.dart';

/// Logo PointageQr réutilisable.
/// [size] : taille du logo en pixels (défaut 80)
/// [showName] : afficher le nom "PointageQr" sous le logo (défaut false)
class AppLogo extends StatelessWidget {
  final double size;
  final bool   showName;
  final bool   darkBackground;

  const AppLogo({
    super.key,
    this.size           = 80,
    this.showName       = false,
    this.darkBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo PNG avec coins arrondis
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.195), // ratio identique à l'icône
          child: Image.asset(
            'assets/logo.png',
            width:  size,
            height: size,
            fit:    BoxFit.cover,
          ),
        ),

        if (showName) ...[
          SizedBox(height: size * 0.15),
          Text(
            'PointageQr',
            style: TextStyle(
              fontSize:   size * 0.28,
              fontWeight: FontWeight.w800,
              color:      darkBackground ? Colors.white : const Color(0xFF1a2540),
              letterSpacing: -0.5,
            ),
          ),
          Text(
            'PRÉSENCE',
            style: TextStyle(
              fontSize:   size * 0.13,
              fontWeight: FontWeight.w400,
              letterSpacing: 2.5,
              color: darkBackground
                ? Colors.white.withOpacity(0.5)
                : const Color(0xFF1a2540).withOpacity(0.4),
            ),
          ),
        ],
      ],
    );
  }
}
