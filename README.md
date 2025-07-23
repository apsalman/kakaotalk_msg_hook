# 카카오톡 메시지 JSON 수신

> **기반 버전**: AutoHotkey v1.1.37.02

---

## 개요

이 소스는 카카오톡 클라이언트의 메모리에서 **주고받는 메시지를 JSON 형식으로 추출**하는 기능을 제공합니다.  
이를 통해 카카오톡 메시지를 실시간으로 감지하고 자동화 작업에 활용할 수 있습니다.
<img width="1083" height="1040" alt="image" src="https://github.com/user-attachments/assets/571c3e89-6aa3-4867-a96b-5fe6b23d4b42" />

---

## 메시지 형식

카카오톡에서 전송/수신되는 메시지는 다음과 같은 **JSON 형식**으로 메모리에 담깁니다:

```json
{
  "attachment": "",
  "authorId": 123456789,
  "chatId": 12345678901234567,
  "logId": 1234567891234567891,
  "message": "테스트 메시지 전송 ㅇㅇ",
  "msgId": 123456789,
  "prevId": 12345678901234567,
  "referer": 0,
  "revision": 0,
  "rewrite": 0,
  "sendAt": 1753245256,
  "supplement": "",
  "type": 1
}
