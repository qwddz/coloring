import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

// Published on animosaic.app next to the puzzles' pages; the Play store
// listing links them too.
final privacyPolicyUrl = Uri.parse('https://animosaic.app/colors/privacy');
final termsOfUseUrl = Uri.parse('https://animosaic.app/colors/terms');
const contactEmail = 'contact@animosaic.app';
final contactEmailUrl = Uri(scheme: 'mailto', path: contactEmail);

/// Opens a link outside the app; replaced in tests.
final externalLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);
