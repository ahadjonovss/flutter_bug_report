import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Takes a picture of what is on screen, from a [RepaintBoundary].
///
/// **Off unless you turn it on, and worth thinking about before you do.** A
/// screenshot carries whatever the screen carried: a customer's name, a phone
/// number, a balance, a message. On a fintech or a health screen that is the
/// most sensitive thing this package could send, and it is sent as a picture
/// nobody can grep for later.
///
/// When it is on, the sheet shows the person the exact image before it goes and
/// lets them drop it. That is the minimum: nobody should discover afterwards
/// what a report contained.
abstract final class Screenshot {
  /// Captures [key]'s subtree, or null if there is nothing to capture yet.
  ///
  /// [pixelRatio] is deliberately low by default. A full-resolution screenshot
  /// of a modern phone is several megabytes, which is the difference between an
  /// attachment that uploads on one bar of signal and one that does not — and
  /// nobody reads a bug report at 3× anyway.
  static Future<Uint8List?> capture(
    GlobalKey key, {
    double pixelRatio = 1.5,
  }) async {
    try {
      final object = key.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return null;

      // A boundary still painting would capture a half-built frame.
      if (object.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      final image = await object.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      return data?.buffer.asUint8List();
    } on Object {
      // A report that arrives without a picture beats one that does not
      // arrive.
      return null;
    }
  }
}
