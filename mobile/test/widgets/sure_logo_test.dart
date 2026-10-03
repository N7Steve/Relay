import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/sure_logo.dart';

void main() {
  testWidgets('renders the logomark at the requested size under the Sure theme',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SureTheme.dark,
        home: const Scaffold(body: Center(child: SureLogo(size: 40))),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/images/relay.png');
    expect(image.width, 40);
    expect(image.height, 40);
    expect(image.semanticLabel, 'Relay');
  });
}
