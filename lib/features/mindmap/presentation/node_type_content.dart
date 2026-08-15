import 'package:flutter/widgets.dart';

import 'node_editors/media_travel_node_editors.dart';
import 'node_editors/productivity_node_editors.dart';

export 'node_editors/productivity_node_editors.dart' show NodeRenderContext;

Widget buildNodeTypeContent(NodeRenderContext context) =>
    buildMediaTravelNodeContent(context);
