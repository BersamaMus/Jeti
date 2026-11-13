// Draws Jeti's icon, a jetty over water on a green tile, into
// windows\runner\resources\app_icon.ico (the exe's and installer's icon),
// assets\icon.png (shown in the app) and the Android launcher icons in
// android\app\src\main\res. Run from the project folder:
//   dart run tool/make_icon.dart
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

// Drawn large and scaled down, which smooths the edges.
const size = 1024;
final green = img.ColorRgba8(0x4A, 0xDE, 0x80, 255);
final ink = img.ColorRgba8(0x05, 0x2E, 0x16, 255);
// Ink at 43% over the green, solid so overlapping strokes don't darken.
final water = img.ColorRgba8(0x2C, 0x92, 0x52, 255);

const res = 'android/app/src/main/res';

// Android's screen densities, and how many pixels a dp is in each.
const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

void main() {
  final icon = img.Image(width: size, height: size, numChannels: 4);
  img.fillRect(icon, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: green, radius: 224);
  _drawWater(icon, water);
  _drawJetty(icon, ink);

  final png = File('assets/icon.png');
  png.parent.createSync(recursive: true);
  png.writeAsBytesSync(img.encodePng(_scaled(icon, 256)));

  final sizes = [256, 64, 48, 40, 32, 24, 20, 16];
  File('windows/runner/resources/app_icon.ico')
      .writeAsBytesSync(img.IcoEncoder().encodeImages([for (final s in sizes) _scaled(icon, s)]));

  _android(icon);
  stdout.writeln('Wrote assets/icon.png, windows/runner/resources/app_icon.ico and the Android icons');
}

/// The Android launcher icons. Android 8 and up shape the icon themselves
/// from a background (the green, in values/colors.xml) and a foreground
/// layer, 108dp square, of which only the middle 66dp or so is sure to show.
/// Older versions show the whole tile as it is.
void _android(img.Image tile) {
  // The tile's 1024px are 68dp of the 108dp layer, which keeps the jetty
  // inside the circle every launcher shows.
  const layer = 1626;
  const inset = (layer - size) ~/ 2;

  final jetty = img.Image(width: size, height: size, numChannels: 4);
  _drawWater(jetty, water);
  _drawJetty(jetty, ink);

  // For themed icons (Android 13+), which colour the shape themselves: the
  // jetty solid and the water fainter, so the two stay apart.
  final waterOnly = img.Image(width: size, height: size, numChannels: 4);
  _drawWater(waterOnly, ink);
  final jettyOnly = img.Image(width: size, height: size, numChannels: 4);
  _drawJetty(jettyOnly, ink);
  final mono = img.Image(width: size, height: size, numChannels: 4);
  for (final p in mono) {
    final alpha = jettyOnly.getPixel(p.x, p.y).a > 0 ? 255 : (waterOnly.getPixel(p.x, p.y).a > 0 ? 110 : 0);
    p.setRgba(0, 0, 0, alpha);
  }

  img.Image onLayer(img.Image art) =>
      img.compositeImage(img.Image(width: layer, height: layer, numChannels: 4), art, dstX: inset, dstY: inset);
  final foreground = onLayer(jetty);
  final monochrome = onLayer(mono);

  for (final MapEntry(key: density, value: scale) in densities.entries) {
    final folder = '$res/mipmap-$density';
    Directory(folder).createSync(recursive: true);
    File('$folder/ic_launcher.png').writeAsBytesSync(img.encodePng(_scaled(tile, (48 * scale).round())));
    final layerPx = (108 * scale).round();
    File('$folder/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(_scaled(foreground, layerPx)));
    File('$folder/ic_launcher_monochrome.png').writeAsBytesSync(img.encodePng(_scaled(monochrome, layerPx)));
  }
}

/// Two waves across the tile.
void _drawWater(img.Image icon, img.Color color) {
  _wave(icon, y: 640, color: color);
  _wave(icon, y: 770, color: color);
}

/// The jetty's deck and its three legs, in front of the water.
void _drawJetty(img.Image icon, img.Color color) {
  img.fillRect(icon, x1: 168, y1: 392, x2: 856, y2: 488, color: color, radius: 32);
  for (final x in [232, 472, 712]) {
    img.fillRect(icon, x1: x, y1: 470, x2: x + 80, y2: 740, color: color, radius: 20);
  }
}

/// A thick sine wave across the tile, drawn as a run of dots.
void _wave(img.Image icon, {required int y, required img.Color color}) {
  for (var x = 150; x <= 874; x += 2) {
    final dy = (sin((x - 150) / 724 * 4 * pi) * 26).round();
    img.fillCircle(icon, x: x, y: y + dy, radius: 30, color: color);
  }
}

img.Image _scaled(img.Image source, int to) =>
    img.copyResize(source, width: to, height: to, interpolation: img.Interpolation.average);
