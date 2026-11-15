class NativePlayer {}

class Player {
  // The real player exposes a platform interface, not a NativePlayer directly.
  final Object platform = NativePlayer();
}

class UserPreferences {
  static const assDirectPlay = 'ass';
}

class Preferences {
  bool get(String key) => true;
}

class Backend {
  final _player = Player();
  final _prefs = Preferences();
  final properties = <String, String>{};
  int? _lastTextColor = 0xffffffff;
  int? _lastBackgroundColor = 0xbf000000;
  int? _lastStrokeColor = 0xff000000;
  double? _lastFontSize = 20;
  int? _lastFontWeight = 700;
  double? _lastVerticalOffset = 0.06;
  Future<void> _nativeSetProperty(NativePlayer n, String k, String v) async {
    properties[k] = v;
  }

  double get _textSubtitleScale => 1;
  Future<void> _refreshStackedSecondaryPosition({required bool force}) async {}
  // @methods@
}

void expect(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final b = Backend();
  final native = b._player.platform as NativePlayer;
  await b._writeSubtitleStyle(native);
  expect(b.properties['sub-border-style'] == 'background-box', 'missing box');
  expect(b.properties['sub-shadow-offset'] == '4', 'missing box padding');
  expect(
    b.properties['sub-back-color'] == '#bf000000',
    'background alpha lost',
  );
  expect(b.properties['sub-bold'] == 'yes', 'bold caption lost');
  expect(b.properties['sub-ass-override'] == 'no', 'authored ASS overridden');
  b._lastBackgroundColor = 0x00000000;
  await b._writeSubtitleStyle(native);
  expect(b.properties['sub-border-style'] == 'outline-and-shadow', 'stale box');
  expect(b.properties['sub-shadow-offset'] == '0', 'stale box padding');
  b._lastBackgroundColor = 0x01000000;
  await b._writeSubtitleStyle(native);
  expect(
    b.properties['sub-border-style'] == 'background-box',
    'low alpha ignored',
  );
  b._lastBackgroundColor = null;
  await b._writeSubtitleStyle(native);
  expect(
    b.properties['sub-border-style'] == 'background-box',
    'omitted color reset',
  );
  print('Moonfin caption background transitions passed');
}
