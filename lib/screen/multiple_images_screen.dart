import 'package:flutter/material.dart';

import 'choose_photo_screen.dart';

class MultipleImagesScreen extends StatelessWidget {
  const MultipleImagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChoosePhotoScreen(allowMultiple: true);
  }
}
