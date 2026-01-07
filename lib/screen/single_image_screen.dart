import 'package:flutter/material.dart';

import 'choose_photo_screen.dart';

class SingleImageScreen extends StatelessWidget {
  const SingleImageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChoosePhotoScreen(allowMultiple: false);
  }
}
