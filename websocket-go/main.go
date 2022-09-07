package main

import (
	"log"
	"net/http"

	"github.com/gorilla/websocket"
	"github.com/pion/webrtc/v3"
)

var (
	upgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool {
			return true
		},
	}
)

func main() {
	log.SetFlags(log.Llongfile)
	http.HandleFunc("/websocket", WebsocketHandler)
	err := http.ListenAndServeTLS(":4800", "certs/server.pem", "certs/server.key", nil)
	if err != nil {
		log.Fatal(err)
	}
	// http.ListenAndServe(":4800", nil)

}

var pc *webrtc.PeerConnection

func WebsocketHandler(w http.ResponseWriter, r *http.Request) {
	unsafeConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Print("upgrade:", err)
		return
	}
	defer unsafeConn.Close()
	log.Println("socket 已经连接")

	offer := webrtc.SessionDescription{}
	err = unsafeConn.ReadJSON(&offer)
	if err != nil {
		log.Fatal(err)
	}
	pc, err = createAnswer()
	if err != nil {
		log.Fatal(err)
	}

	pc.OnICECandidate(func(i *webrtc.ICECandidate) {
		if i != nil {
			log.Println("发送ICE", i.ToJSON())
			err = unsafeConn.WriteJSON(i.ToJSON())
			if err != nil {
				log.Fatal(err)
			}
		}
	})

	log.Println("接收到offer并设置", offer)
	err = pc.SetRemoteDescription(offer)
	if err != nil {
		log.Fatal(err)
	}
	answer, err := pc.CreateAnswer(nil)
	if err != nil {
		log.Fatal(err)
	}
	log.Println("设置answer")
	err = pc.SetLocalDescription(answer)
	if err != nil {
		log.Fatal(err)
	}

	log.Println("发送answer")
	err = unsafeConn.WriteJSON(answer)
	if err != nil {
		log.Fatal(err)
	}

	for {
		candidate := webrtc.ICECandidateInit{}
		err = unsafeConn.ReadJSON(&candidate)
		if err != nil {
			log.Println(err)
			log.Println("websocket 关闭")
			return
		}
		log.Println("设置ICE", candidate)
		pc.AddICECandidate(candidate)
	}
}

// 创建WEBRTC answer 端
func createAnswer() (*webrtc.PeerConnection, error) {
	config := webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{},
	}
	var err error
	peerConnection, err := webrtc.NewPeerConnection(config)
	if err != nil {
		log.Println(err)
		return nil, err
	}
	peerConnection.OnConnectionStateChange(func(s webrtc.PeerConnectionState) {
		log.Println("Peer Connection State has changed: ", s.String())
	})

	peerConnection.OnDataChannel(func(dc *webrtc.DataChannel) {
		dc.OnOpen(func() {
			log.Println("=== open")
		})
		dc.OnMessage(func(msg webrtc.DataChannelMessage) {
			log.Println("message ==>", string(msg.Data))

			dc.SendText("offer ==== >>" + string(msg.Data))
		})
		dc.OnClose(func() {
			log.Println("=== close")
		})
	})

	return peerConnection, nil
}
