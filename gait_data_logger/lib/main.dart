// Flutter Sensor Data Logger App
// ignore_for_file: library_private_types_in_public_api, avoid_print, prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:csv/csv.dart';
import 'package:open_file_plus/open_file_plus.dart';

void main() => runApp(const SensorLoggerApp());

class SensorLoggerApp extends StatelessWidget {
  const SensorLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoggingHome(),
    );
  }
}

class LoggingHome extends StatefulWidget {
  const LoggingHome({super.key});

  @override
  _LoggingHomeState createState() => _LoggingHomeState();
}

class _LoggingHomeState extends State<LoggingHome> {
  late WebSocketChannel channel;
  bool loggingActive = false;
  List<List<String>> csvData = [
    [
      "Timestamp",
      "M_1_G_X",
      "M_1_G_Y",
      "M_1_G_Z",
      "M_1_A_X",
      "M_1_A_Y",
      "M_1_A_Z",
      "M_2_G_X",
      "M_2_G_Y",
      "M_2_G_Z",
      "M_2_A_X",
      "M_2_A_Y",
      "M_2_A_Z",
      "M_3_G_X",
      "M_3_G_Y",
      "M_3_G_Z",
      "M_3_A_X",
      "M_3_A_Y",
      "M_3_A_Z",
      "M_4_G_X",
      "M_4_G_Y",
      "M_4_G_Z",
      "M_4_A_X",
      "M_4_A_Y",
      "M_4_A_Z",
      "F_1",
      "F_2"
    ]
  ];
  String displayedData = "";
  String? csvFilePath;
  bool stanceSwingEnabled = false; // Tracks switch status
  String leftStanceSwing = ""; // Tracks current value (L-St or L-Sw)
  bool isLoggingStarted = false; // Tracks logging state

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  void startLogging(String url) {
    channel = WebSocketChannel.connect(Uri.parse(url));
    setState(() {
      loggingActive = true;
    });
    print('herer');
    print(channel.toString());
    channel.stream.listen((message) {
      print('processinh');
      processMessage(message);
    }, onError: (error) {
      showMessage("WebSocket Error: $error");
      print(error);
    }, onDone: () {
      setState(() {
        loggingActive = false;
      });
      showMessage("WebSocket Closed.");
    });
  }

  void stopLogging() {
    channel.sink.close();
    setState(() {
      loggingActive = false;
    });
    showMessage("Logging Stopped.");
  }

  void resetData() {
    setState(() {
      displayedData = "";
      csvData = [
        [
          "Timestamp",
          "M_1_G_X",
          "M_1_G_Y",
          "M_1_G_Z",
          "M_1_A_X",
          "M_1_A_Y",
          "M_1_A_Z",
          "M_2_G_X",
          "M_2_G_Y",
          "M_2_G_Z",
          "M_2_A_X",
          "M_2_A_Y",
          "M_2_A_Z",
          "M_3_G_X",
          "M_3_G_Y",
          "M_3_G_Z",
          "M_3_A_X",
          "M_3_A_Y",
          "M_3_A_Z",
          "M_4_G_X",
          "M_4_G_Y",
          "M_4_G_Z",
          "M_4_A_X",
          "M_4_A_Y",
          "M_4_A_Z",
          "F_1",
          "F_2"
        ]
      ];
    });
    showMessage("Data Reset Successfully.");
  }

void processMessage(String message) {
  String timestamp = DateTime.now().toString();
  List<String> dataLines = message.split('\n');

  // Extract MPU and Flex Sensor Data
  List<String> mpuData = dataLines
      .where((line) => line.contains("MPU6050"))
      .expand((line) => line.split(', '))
      .toList();

  List<String> flexData = dataLines
      .where((line) => line.contains("Bend Sensor"))
      .expand((line) => line.split(', '))
      .toList();

  Map<String, String> mpuValues = {};
  for (var line in mpuData) {
    RegExp regex = RegExp(
        r'MPU6050 (\d) Gyro X=([-\d.]+) Y=([-\d.]+) Z=([-\d.]+) Accel X=([-\d.]+) Y=([-\d.]+) Z=([-\d.]+)');
    Match? match = regex.firstMatch(line);
    if (match != null) {
      String sensorNum = match.group(1)!;
      mpuValues['M_${sensorNum}_G_X'] = match.group(2)!;
      mpuValues['M_${sensorNum}_G_Y'] = match.group(3)!;
      mpuValues['M_${sensorNum}_G_Z'] = match.group(4)!;
      mpuValues['M_${sensorNum}_A_X'] = match.group(5)!;
      mpuValues['M_${sensorNum}_A_Y'] = match.group(6)!;
      mpuValues['M_${sensorNum}_A_Z'] = match.group(7)!;
    }
  }

  Map<String, String> flexValues = {};
  for (int i = 0; i < flexData.length; i++) {
    RegExp regex = RegExp(r'Bend Sensor (\d): (.+?) ohms');
    Match? match = regex.firstMatch(flexData[i]);
    if (match != null) {
      String sensorNum = match.group(1)!;
      flexValues["F_$sensorNum"] = match.group(2)!;
    }
  }

  setState(() {
    String stanceSwingValue = stanceSwingEnabled ? leftStanceSwing : "";

    csvData.add([
      timestamp,
      ...mpuValues.values,
      ...flexValues.values,
      if (stanceSwingEnabled) stanceSwingValue,
    ]);

    String display = "$timestamp\n" +
        mpuValues.entries.map((e) => "${e.key}: ${e.value}").join('\n') +
        '\n' +
        flexValues.entries.map((e) => "${e.key}: ${e.value}").join('\n') +
        '\n' +
        (stanceSwingEnabled ? "L_St_Sw: $stanceSwingValue\n" : "");

    displayedData = "$display$displayedData";
  });
}


  Future<void> viewCsvFile() async {
    final directory = await getApplicationDocumentsDirectory();
    String timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    csvFilePath = '${directory.path}/sensor_data_$timestamp.csv';
    String csvContent = const ListToCsvConverter().convert(csvData);
    File csvFile = File(csvFilePath!);
    await csvFile.writeAsString(csvContent);
    await OpenFile.open(csvFilePath);
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    TextEditingController urlController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text("Sensor Data Logger")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: "WebSocket URL",
                hintText: "ws://192.168.4.1/ws",
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent),
                ),
                child: displayedData.isNotEmpty
                    ? SingleChildScrollView(
                        child: Text(displayedData,
                            style: const TextStyle(fontSize: 14)),
                      )
                    : const SizedBox(
                        width: double.infinity,
                      ),
              ),
            ),
            const SizedBox(height: 20),
            loggingActive
                ? ElevatedButton(
                    onPressed: stopLogging,
                    child: const Text("Stop Logging"),
                  )
                : ElevatedButton(
                    onPressed: () {
                      if (urlController.text.isNotEmpty) {
                        startLogging(urlController.text);
                      } else {
                        startLogging("ws://192.168.4.1/ws");
                      }
                    },
                    child: const Text("Start Logging"),
                  ),
            if (!loggingActive && csvData.isNotEmpty)
              ElevatedButton(
                onPressed: viewCsvFile,
                child: const Text("View CSV File"),
              ),
            if (!loggingActive)
              ElevatedButton(
                onPressed: resetData,
                child: const Text("Reset"),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Stance/Swing"),
                Switch(
                  value: stanceSwingEnabled,
                  onChanged: (value) {
                    setState(() {
                      stanceSwingEnabled = value;
                      if (stanceSwingEnabled &&
                          !csvData[0].contains("L_St_Sw")) {
                        csvData[0].add("L_St_Sw");
                      } else if (csvData[0].contains("L_St_Sw")) {
                        csvData[0].remove("L_St_Sw");
                      }
                    });
                  },
                ),
              ],
            ),
            if (stanceSwingEnabled && loggingActive) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        leftStanceSwing = "L-St";
                      });
                    },
                    child: const Text("L-Stance"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        leftStanceSwing = "L-Sw";
                      });
                    },
                    child: const Text("L-Swing"),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
