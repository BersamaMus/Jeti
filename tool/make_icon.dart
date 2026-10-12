// Draws Jeti's icon, a jetty over water on a green tile, into
// windows\runner\resources\app_icon.ico (the exe's and installer's icon) and
// assets\icon.png (shown in the app). Run from the project folder:
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

void main() {
  final icon = img.Image(width: size, height: size, numChannels: 4);

  // The tile, then the water, then the jetty in front of it.
  img.fillRect(icon, x1: 0, y1: 0, x2: size - 1, y2: size - 1, color: green, radius: 224);
  _wave(icon, y: 640);
  _wave(icon, y: 770);
  img.fillRect(icon, x1: 168, y1: 392, x2: 856, y2: 488, color: ink, radius: 32);
  for (final x in [232, 472, 712]) {
    img.fillRect(icon, x1: x, y1: 470, x2: x + 80, y2: 740, color: ink, radius: 20);
  }

  final png = File('assets/icon.png');
  png.parent.createSync(recursive: true);
  png.writeAsBytesSync(img.encodePng(_scaled(icon, 256)));

  final sizes = [256, 64, 48, 40, 32, 24, 20, 16];
  File('windows/runner/resources/app_icon.ico')
      .writeAsBytesSync(img.IcoEncoder().encodeImages([for (final s in sizes) _scaled(icon, s)]));
  stdout.writeln('Wrote assets/icon.png and windows/runner/resources/app_icon.ico');
}

/// A thick sine wave across the tile, drawn as a run of dots.
void _wave(img.Image icon, {required int y}) {
  for (var x = 150; x <= 874; x += 2) {
    final dy = (sin((x - 150) / 724 * 4 * pi) * 26).round();
    img.fillCircle(icon, x: x, y: y + dy, radius: 30, color: water);
  }
}

img.Image _scaled(img.Image source, int to) =>
    img.copyResize(source, width: to, height: to, interpolation: img.Interpolation.average);
