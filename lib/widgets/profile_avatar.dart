import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class ProfileAvatar extends StatelessWidget {
  final Uint8List? imageBytes;
  final String name;
  final double radius;

  const ProfileAvatar({
    super.key,
    required this.imageBytes,
    required this.name,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null && imageBytes!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.brand,
      backgroundImage: hasImage ? MemoryImage(imageBytes!) : null,
      child: hasImage
          ? null
          : Text(
              _initials(name),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.8,
              ),
            ),
    );
  }

  String _initials(String name) {
    final parts =
        name.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }
}
