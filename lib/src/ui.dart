import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'enumerate_items.dart';
import 'network_event.dart';
import 'network_logger.dart';

/// Overlay for [NetworkLoggerButton].
class NetworkLoggerOverlay extends StatefulWidget {
  NetworkLoggerOverlay._({Key? key}) : super(key: key);

  /// Attach overlay to specified [context].
  static OverlayEntry attachTo(
    BuildContext context, {
    bool rootOverlay = true,
  }) {
    // create overlay entry
    var entry = OverlayEntry(
      builder: (context) => NetworkLoggerOverlay._(),
    );
    // insert on next frame
    Future.delayed(Duration.zero, () {
      Overlay.of(context, rootOverlay: rootOverlay).insert(entry);
    });
    // return
    return entry;
  }

  @override
  State<NetworkLoggerOverlay> createState() => _NetworkLoggerOverlayState();
}

class _NetworkLoggerOverlayState extends State<NetworkLoggerOverlay> {
  Offset _offset = Offset(-10, 100);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Positioned(
      right: _offset.dx,
      bottom: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _offset -= details.delta;
            if (_offset.dx < -35) {
              _offset = Offset(-35, _offset.dy);
            } else if (_offset.dx > (screen.width - 20)) {
              _offset = Offset((screen.width - 20), _offset.dy);
            }
            if (_offset.dy < -35) {
              _offset = Offset(_offset.dx, -35);
            } else if (_offset.dy > (screen.height - 20)) {
              _offset = Offset(_offset.dx, (screen.height - 20));
            }
          });
        },
        child: SizedBox(
          width: 56,
          height: 56,
          child: NetworkLoggerButton(),
        ),
      ),
    );
  }
}

/// [FloatingActionButton] that opens [NetworkLoggerScreen] when pressed.
class NetworkLoggerButton extends StatefulWidget {
  final NetworkEventList? eventList;
  final Duration blinkPeriod;
  final Color color;

  NetworkLoggerButton({
    Key? key,
    this.color = Colors.deepOrange,
    this.blinkPeriod = const Duration(seconds: 1, microseconds: 500),
    NetworkEventList? eventList,
  })  : this.eventList = eventList ?? NetworkLogger.instance,
        super(key: key);

  @override
  _NetworkLoggerButtonState createState() => _NetworkLoggerButtonState();
}

class _NetworkLoggerButtonState extends State<NetworkLoggerButton> {
  StreamSubscription? _subscription;
  Timer? _blinkTimer;
  bool _visible = true;
  int _blink = 0;

  Future<void> _press() async {
    setState(() {
      _visible = false;
    });
    try {
      await NetworkLoggerScreen.open(context);
    } finally {
      if (mounted) {
        setState(() {
          _visible = true;
        });
      }
    }
  }

  @override
  void initState() {
    _subscription = NetworkLogger.instance.stream.listen((event) {
      if (mounted) {
        setState(() {
          _blink = _blink % 2 == 0 ? 6 : 5;
        });
      }
    });

    _blinkTimer = Timer.periodic(widget.blinkPeriod, (timer) {
      if (_blink > 0 && mounted) {
        setState(() {
          _blink--;
        });
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _visible
        ? FloatingActionButton(
            child: Icon(
              (_blink % 2 == 0) ? Icons.cloud : Icons.cloud_queue,
              color: Colors.white,
            ),
            onPressed: _press,
            backgroundColor: widget.color,
          )
        : SizedBox();
  }
}

/// Screen that displays log entries list.
class NetworkLoggerScreen extends StatelessWidget {
  NetworkLoggerScreen({Key? key, NetworkEventList? eventList})
      : this.eventList = eventList ?? NetworkLogger.instance,
        super(key: key);

  /// Event list to listen for event changes.
  final NetworkEventList eventList;

  /// Opens screen.
  static Future<void> open(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NetworkLoggerScreen(),
      ),
    );
  }

  final TextEditingController searchController = TextEditingController(text: null);

  /// filte events with search keyword
  List<NetworkEvent> getEvents() {
    if (searchController.text.isEmpty) return eventList.events;
    final query = searchController.text.toLowerCase();
    return eventList.events.where((it) => it.request?.uri.toLowerCase().contains(query) ?? false).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Network Logs'),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => eventList.clear(),
            ),
          ],
        ),
        body: StreamBuilder(
          stream: eventList.stream,
          builder: (context, snapshot) {
            //filte events with search keyword
            final events = getEvents();
            return Column(
              children: [
                TextField(
                  controller: searchController,
                  onChanged: (text) {
                    eventList.updated(NetworkEvent());
                  },
                  autocorrect: false,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    filled: true,
                    // fillColor: Colors.white,
                    prefixIcon: Icon(
                      Icons.search,
                      // color: Colors.black26,
                    ),
                    suffix: Text(getEvents().length.toString() + ' results'),
                    hintText: "enter keyword to search",
                    // focusedBorder: OutlineInputBorder(
                    //   borderSide: BorderSide(color: Colors.white),
                    //   borderRadius: const BorderRadius.all(
                    //     const Radius.circular(0.0),
                    //   ),
                    // ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: events.length,
                    itemBuilder: enumerateItems<NetworkEvent>(
                      events,
                      (context, item) => ListTile(
                        key: ValueKey(item.request),
                        title: Text(
                          item.request!.method,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          item.request!.uri.toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: Icon(
                          item.error == null
                              ? (item.response == null ? Icons.hourglass_empty : Icons.done)
                              : Icons.close,
                          color: item.error == null ? (item.response == null ? Colors.grey : Colors.green) : Colors.red,
                        ),
                        trailing: AutoUpdate(
                          duration: Duration(seconds: 1),
                          builder: (context) => Text(_timeDifference(item.timestamp!)),
                        ),
                        onTap: () => NetworkLoggerEventScreen.open(
                          context,
                          item,
                          eventList,
                        ),
                      ),
                    ),
                  ),
                )
              ],
            );
          },
        ),
      ),
    );
  }
}

String _timeDifference(DateTime time, [DateTime? origin]) {
  origin ??= DateTime.now();
  var delta = origin.difference(time);
  if (delta.inSeconds < 90) {
    return '${delta.inSeconds} s';
  } else if (delta.inMinutes < 90) {
    return '${delta.inMinutes} m';
  } else {
    return '${delta.inHours} h';
  }
}

final _jsonEncoder = JsonEncoder.withIndent('  ');

/// Screen that displays log entry details.
class NetworkLoggerEventScreen extends StatelessWidget {
  const NetworkLoggerEventScreen({Key? key, required this.event}) : super(key: key);

  static Route<void> route({
    required NetworkEvent event,
    required NetworkEventList eventList,
  }) {
    return MaterialPageRoute(
      builder: (context) => StreamBuilder(
        stream: eventList.stream.where((item) => item.event == event),
        builder: (context, snapshot) => NetworkLoggerEventScreen(event: event),
      ),
    );
  }

  /// Opens screen.
  static Future<void> open(
    BuildContext context,
    NetworkEvent event,
    NetworkEventList eventList,
  ) {
    return Navigator.of(context).push(route(
      event: event,
      eventList: eventList,
    ));
  }

  /// Which event to display details for.
  final NetworkEvent event;

  Widget buildBodyViewer(BuildContext context, dynamic body, {Color color = Colors.black}) {
    String text;
    if (body == null) {
      text = '';
    } else if (body is String) {
      text = body;
    } else if (body is List || body is Map) {
      text = _jsonEncoder.convert(body);
    } else {
      text = body.toString();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Copied to clipboard'),
            behavior: SnackBarBehavior.floating,
          ));
        },
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['sans-serif'],
            color: color,
          ),
        ),
      ),
    );
  }

  Widget buildHeadersViewer(
    BuildContext context,
    List<MapEntry<String, String>> headers,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: headers.map((e) => SelectableText(e.key)).toList(),
          ),
          SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: headers.map((e) => SelectableText(e.value)).toList(),
          ),
        ],
      ),
    );
  }

  Widget buildRequestView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 5),
          child: Text('URL', style: Theme.of(context).textTheme.bodySmall),
        ),
        SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.request!.method,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              SizedBox(width: 15),
              Expanded(child: SelectableText(event.request!.uri.toString())),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
          child: Text('TIMESTAMP', style: Theme.of(context).textTheme.bodySmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Text(event.timestamp.toString()),
        ),
        if (event.request!.headers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
            child: Text('HEADERS', style: Theme.of(context).textTheme.bodySmall),
          ),
          buildHeadersViewer(context, event.request!.headers.entries),
        ],
        if (event.error != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
            child: Text('ERROR', style: Theme.of(context).textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Text(
              event.error.toString(),
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
          child: Text('BODY', style: Theme.of(context).textTheme.bodySmall),
        ),
        buildBodyViewer(context, event.request!.data),
      ],
    );
  }

  Widget buildResponseView(BuildContext context) {
    final statusCode = event.response?.statusCode ?? 0;
    final color = (statusCode >= 200 && statusCode <= 299) ? Colors.green : Colors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 5),
          child: Text('RESULT', style: Theme.of(context).textTheme.bodySmall),
        ),
        SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.response!.statusCode.toString(),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
              ),
              SizedBox(width: 15),
              Expanded(
                  child: Text(
                event.response!.statusMessage,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
              )),
            ],
          ),
        ),
        if (event.response?.headers.isNotEmpty ?? false) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
            child: Text('HEADERS', style: Theme.of(context).textTheme.bodySmall),
          ),
          buildHeadersViewer(
            context,
            event.response?.headers.entries ?? [],
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
          child: Text('BODY', style: Theme.of(context).textTheme.bodySmall),
        ),
        buildBodyViewer(context, event.response?.data, color: color),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showResponse = event.response != null;
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Log Entry'),
          // bottom: (bottom as PreferredSizeWidget?),
        ),
        body: Builder(
            builder: (context) => SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Request',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      buildRequestView(context),
                      if (showResponse) ...[
                        const Divider(height: 32, thickness: 1),
                        Text('Response', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        buildResponseView(context),
                      ],
                    ],
                  ),
                )),
      ),
    );
  }
}

/// Widget builder that re-builds widget repeatedly with [duration] interval.
class AutoUpdate extends StatefulWidget {
  const AutoUpdate({Key? key, required this.duration, required this.builder}) : super(key: key);

  /// Re-build interval.
  final Duration duration;

  /// Widget builder to build widget.
  final WidgetBuilder builder;

  @override
  _AutoUpdateState createState() => _AutoUpdateState();
}

class _AutoUpdateState extends State<AutoUpdate> {
  Timer? _timer;

  void _setTimer() {
    _timer = Timer.periodic(widget.duration, (timer) {
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(AutoUpdate old) {
    if (old.duration != widget.duration) {
      _timer?.cancel();
      _setTimer();
    }
    super.didUpdateWidget(old);
  }

  @override
  void initState() {
    _setTimer();
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}
