// Small-screen layout helpers (layout only, no behaviour changes).
//
// fitAppBarActions: on narrow phones (or with large system font) a long
// AppBar action list squeezes the title to nothing. Keep as many icons as
// fit and move the rest, unchanged, into a "More" menu. Each moved icon keeps
// its own onPressed and uses its tooltip as the menu label.
import 'package:flutter/material.dart';

List<Widget> fitAppBarActions(
  BuildContext context,
  List<Widget> actions, {
  double reserveForTitle = 150,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final slots = ((width - reserveForTitle) / kMinInteractiveDimension).floor().clamp(1, 99);
  if (actions.length <= slots) return actions;

  final pinned = <Widget>[];
  final movable = <IconButton>[];
  for (final a in actions) {
    if (a is IconButton && a.onPressed != null) {
      movable.add(a);
    } else {
      pinned.add(a);
    }
  }
  // Room left for icons after the pinned widgets and the "More" button.
  final keep = (slots - pinned.length - 1).clamp(0, movable.length);
  if (keep >= movable.length) return actions;
  final shown = movable.take(keep).toList();
  final hidden = movable.skip(keep).toList();
  final shownSet = shown.toSet();

  final out = <Widget>[
    for (final a in actions)
      if (a is! IconButton || a.onPressed == null || shownSet.contains(a)) a,
  ];
  out.add(PopupMenuButton<int>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert),
    onSelected: (i) => hidden[i].onPressed?.call(),
    itemBuilder: (_) => [
      for (var i = 0; i < hidden.length; i++)
        PopupMenuItem<int>(
          value: i,
          child: Row(children: [
            IconTheme.merge(data: const IconThemeData(size: 20), child: hidden[i].icon),
            const SizedBox(width: 12),
            Flexible(
              child: Text(hidden[i].tooltip ?? 'Action ${i + 1}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
    ],
  ));
  return out;
}
