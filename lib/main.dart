import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// websocket 相关
import 'dart:io';
import 'package:web_socket_channel/io.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              true; // add your localhost detection logic here if you want
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {}
  @override
  void dispose() {
    socketChannel.sink.close();
    peerConnection.close();
  }

  late String inputValue = "";
  // websocket状态
  late String websocketOpen = "连接websocket";
  // webrtc状态
  late String webrtcOpen = "连接webrtc";

  late TextEditingController _controller = TextEditingController();

  var msgList = <Widget>[];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ElevatedButton(
                onPressed: websocketOpen != "连接websocket"
                    ? null
                    : () {
                        webSocket();
                      },
                child: Text(websocketOpen)),
            ElevatedButton(
                onPressed: webrtcOpen == "Webrtc连接中..." ||
                        websocketOpen == "连接websocket"
                    ? null
                    : () {
                        createPeerConnection();
                      },
                child: Text(webrtcOpen)),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: "发送数据"),
              onChanged: (newValue) => inputValue = newValue,
            ),
            ElevatedButton(
                onPressed: webrtcOpen != "断开webrtc连接"
                    ? null
                    : () {
                        if (inputValue == "") {
                          return;
                        }
                        dataChannel.send(RTCDataChannelMessage(inputValue));
                        setState(() {
                          msgList.insert(0, Text('发送：$inputValue'));
                          _controller.text = "";
                          inputValue = "";
                        });
                      },
                child: const Text("发送")),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: msgList,
            )
          ],
        ));
  }

// 创建RTC 连接句柄
  late RTCPeerConnection peerConnection;
  late RTCDataChannel dataChannel;
  createPeerConnection() async {
    if (webrtcOpen == "断开webrtc连接") {
      peerConnection.close();
      return;
    }
    setState(() {
      webrtcOpen = "Webrtc连接中...";
    });
    var configuration = <String, dynamic>{};

    peerConnection =
        await RTCFactoryNative.instance.createPeerConnection(configuration, {});

    peerConnection.onIceConnectionState = (state) {
      // print("++++++++++++++++++++onIceConnectionState  ${state}");
    };

    peerConnection.onIceCandidate = (candidate) {
      // 此处要把信息发送出去
      var data = jsonEncode(candidate.toMap());
      sendData(data);
    };

    peerConnection.onConnectionState = (state) {
      print("onConnectionState===============>  ${state}");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        // 连接成功 关闭websocket
        socketChannel.sink.close();
        setState(() {
          webrtcOpen = "断开webrtc连接";
        });
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        // 断开连接
        setState(() {
          webrtcOpen = "连接webrtc";
          websocketOpen = "连接websocket";
        });
      }
    };

    dataChannel = await peerConnection.createDataChannel(
        "label", RTCDataChannelInit()..id = 1);

    dataChannel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        dataChannel
            .send(RTCDataChannelMessage('(dc1 ==> dc2) Hello from dc1 !!!'));
      }
    };

    dataChannel.onMessage = (data) {
      print("onMessage ${data.text}");
      setState(() {
        msgList.insert(0, Text('接收：${data.text}'));
        if (msgList.length > 99) {
          msgList.removeRange(99, msgList.length);
        }
      });
    };

    offerdescription = await peerConnection.createOffer({});
    peerConnection.setLocalDescription(offerdescription);
    var data = jsonEncode(offerdescription.toMap());

    sendData(data);
  }

  late RTCSessionDescription offerdescription;

  late IOWebSocketChannel socketChannel;
  webSocket() async {
    setState(() {
      websocketOpen = "websocket连接中...";
    });
    WebSocket.connect("wss://x.x.x.x:4800/websocket").then((ws) {
      setState(() {
        websocketOpen = "websocket连接成功";
      });
      // create the stream channel
      socketChannel = IOWebSocketChannel(ws);

      var check = true;
      socketChannel.stream.listen(
        (event) {
          var da = json.decode(event);

          if (check) {
            var answerdescription =
                RTCSessionDescription(da["sdp"], da["type"]);
            peerConnection.setRemoteDescription(answerdescription);
          } else {
            print("接收 ICE ${da}");
            var candidate = RTCIceCandidate(
                da["candidate"], da["sdpMid"], da["sdpMLineIndex"]);
            peerConnection.addCandidate(candidate);
          }
          check = false;
        },
        onError: (err) {
          print("onDeoneError =========>> ${err}");
        },
        onDone: () {
          setState(() {});
        },
      );
    }).catchError((onError) {
      print("onError==>  ${onError}");
      setState(() {
        websocketOpen = "连接websocket";
      });
    });

    // socketChannel =
    //     IOWebSocketChannel.connect('wss://x.x.x.x:48001/websocket');
  }

  sendData(data) {
    socketChannel.sink.add(data);
  }
}
