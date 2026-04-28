import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

void main() {
  runApp(MyApp());
}

// ================= APP =================

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home MQTT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: ConnectionScreen(),
    );
  }
}

// ================= CONNECTION SCREEN =================

class ConnectionScreen extends StatefulWidget {
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late MqttBrowserClient client;

  // ✅ MORE STABLE BROKER
  final String wsUrl = "wss://test.mosquitto.org:8081/mqtt";

  bool connecting = false;
  String status = "Disconnected";

  Future<void> connect() async {
    setState(() {
      connecting = true;
      status = "Connecting...";
    });

    final clientId = "flutter_${DateTime.now().millisecondsSinceEpoch}";

    client = MqttBrowserClient(wsUrl, clientId);

    // 🔧 IMPORTANT SETTINGS
    client.port = 8081;
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.resubscribeOnAutoReconnect = true;
    client.websocketProtocols = ['mqtt'];

    client.logging(on: true);

    // 🔥 STATUS CALLBACKS
    client.onConnected = () {
      print("Connected");
      setState(() {
        status = "Connected ✅";
      });
    };

    client.onDisconnected = () {
      print("Disconnected");
      setState(() {
        status = "Disconnected ❌";
      });
    };

    client.onSubscribed = (topic) {
      print("Subscribed to $topic");
    };

    final message = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    client.connectionMessage = message;

    try {
      await client.connect();
    } catch (e) {
      print("Connection error: $e");

      client.disconnect();

      setState(() {
        connecting = false;
        status = "Connection Failed ❌";
      });

      return;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      setState(() {
        connecting = false;
        status = "Connected ✅";
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(client: client),
        ),
      );
    } else {
      client.disconnect();
      setState(() {
        connecting = false;
        status = "Disconnected ❌";
      });
    }
  }

  @override
  void initState() {
    super.initState();
    connect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("MQTT Connection")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (connecting) CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(status),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: connect,
              child: Text("Retry"),
            )
          ],
        ),
      ),
    );
  }
}

// ================= DASHBOARD =================

class DashboardScreen extends StatefulWidget {
  final MqttBrowserClient client;

  DashboardScreen({required this.client});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool light = false;
  bool fan = false;
  bool ac = false;

  @override
  void initState() {
    super.initState();
    subscribe();
  }

  void subscribe() {
    widget.client.subscribe('home/light', MqttQos.atLeastOnce);
    widget.client.subscribe('home/fan', MqttQos.atLeastOnce);
    widget.client.subscribe('home/ac', MqttQos.atLeastOnce);

    widget.client.updates?.listen((events) {
      final recMess = events[0].payload as MqttPublishMessage;

      final message = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      final topic = events[0].topic;

      print("Topic: $topic  Message: $message");

      setState(() {
        if (topic == 'home/light') light = message == "ON";
        if (topic == 'home/fan') fan = message == "ON";
        if (topic == 'home/ac') ac = message == "ON";
      });
    });
  }

  void publish(String topic, String msg) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(msg);

    widget.client.publishMessage(
      topic,
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  Widget device(String name, bool value, Function(bool) onChanged) {
    return Card(
      child: SwitchListTile(
        title: Text(name),
        value: value,
        onChanged: (v) {
          onChanged(v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Smart Home Dashboard"),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              widget.client.disconnect();
              Navigator.pop(context);
            },
          )
        ],
      ),
      body: Column(
        children: [
          device("Light", light, (v) {
            setState(() => light = v);
            publish("home/light", v ? "ON" : "OFF");
          }),
          device("Fan", fan, (v) {
            setState(() => fan = v);
            publish("home/fan", v ? "ON" : "OFF");
          }),
          device("AC", ac, (v) {
            setState(() => ac = v);
            publish("home/ac", v ? "ON" : "OFF");
          }),
        ],
      ),
    );
  }
}