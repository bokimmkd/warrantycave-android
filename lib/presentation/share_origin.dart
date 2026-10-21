import 'package:flutter/material.dart';

// UIKit requires a popover anchor when presenting a share sheet on iPad.
Rect? shareOrigin(BuildContext context) {
  final object = context.findRenderObject();
  if (object is RenderBox &&
      object.hasSize &&
      object.size.isFinite &&
      !object.size.isEmpty) {
    return object.localToGlobal(Offset.zero) & object.size;
  }
  return null;
}
