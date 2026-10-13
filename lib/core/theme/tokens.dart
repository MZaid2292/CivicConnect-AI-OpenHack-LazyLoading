import 'package:flutter/material.dart';

class Space {
  const Space._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const gapXs = SizedBox(width: xs, height: xs);
  static const gapSm = SizedBox(width: sm, height: sm);
  static const gapMd = SizedBox(width: md, height: md);
  static const gapLg = SizedBox(width: lg, height: lg);
  static const gapXl = SizedBox(width: xl, height: xl);
}

class Radii {
  const Radii._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static final brSm = BorderRadius.circular(sm);
  static final brMd = BorderRadius.circular(md);
  static final brLg = BorderRadius.circular(lg);
  static final brXl = BorderRadius.circular(xl);
}

class Breakpoints {
  const Breakpoints._();

  static const double medium = 600;

  static const double expanded = 900;

  static const double large = 1200;
}

enum WindowSize { compact, medium, expanded, large }

WindowSize windowSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= Breakpoints.large) return WindowSize.large;
  if (w >= Breakpoints.expanded) return WindowSize.expanded;
  if (w >= Breakpoints.medium) return WindowSize.medium;
  return WindowSize.compact;
}

class Motion {
  const Motion._();
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}
