import 'package:flutter/widgets.dart';
/// The Relay mark, shared by all in-app branding surfaces.
class SureLogo extends StatelessWidget {
  const SureLogo({super.key, this.size = 36});

  /// Square edge length in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/relay.png',
      width: size,
      height: size,
      semanticLabel: 'Relay',
    );
  }
}
