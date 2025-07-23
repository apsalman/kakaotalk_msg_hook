#Include <classMemory>
#SingleInstance Force

; 전역 변수
global mem := ""
global lastFoundAddress := 0
global searchRange := 0x10000
global processedMessages := {}
global messageBuffer := []  ; 메시지 버퍼 (정렬용)
global isRunning := false

; GUI 생성
Gui, Add, Text,, 카카오톡 JSON
Gui, Add, Button, x10 y30 w70 h30 gStartMonitor, 시작
Gui, Add, Button, x90 y30 w70 h30 gStopMonitor, 정지
Gui, Add, Button, x170 y30 w70 h30 gClearOutput, 지우기
Gui, Add, Button, x250 y30 w70 h30 gScrollToTop, 맨위로
Gui, Add, Button, x330 y30 w70 h30 gSaveToFile, 저장
Gui, Add, Edit, x10 y70 w1000 h400 ReadOnly vOutput +HScroll
Gui, Show, w1020 h490, 카카오톡 추출

return

; 모니터링 시작
StartMonitor:
    if (isRunning) {
        return
    }
    
    ; 카카오톡 프로세스 연결
    if (!ConnectKakao()) {
        ; 기존 내용 가져오기
        GuiControlGet, currentContent, , Output
        newContent := "[ERROR] 카카오톡 프로세스를 찾을 수 없습니다.`r`n" . currentContent
        GuiControl,, Output, %newContent%
        return
    }
    
    isRunning := true
    ; 기존 내용 가져오기
    GuiControlGet, currentContent, , Output
    newContent := "[INFO] 모니터링 시작...`r`n" . currentContent
    GuiControl,, Output, %newContent%
    SetTimer, CollectJSON, 100  ; 100ms 간격
return

; 모니터링 정지
StopMonitor:
    isRunning := false
    SetTimer, CollectJSON, Off
    ; 기존 내용 가져오기
    GuiControlGet, currentContent, , Output
    newContent := "[INFO] 모니터링 정지`r`n" . currentContent
    GuiControl,, Output, %newContent%
return

; 출력 지우기
ClearOutput:
    GuiControl,, Output,
    messageBuffer := []  ; 버퍼도 초기화
return

; 맨 위로 스크롤
ScrollToTop:
    ; Edit 컨트롤의 커서를 맨 위로 이동
    ControlFocus, Edit1, JSON 추출기 (시간순 정렬)
    Send, ^{Home}
return

; 카카오톡 프로세스 연결
ConnectKakao() {
    processNames := ["KakaoTalk.exe", "kakaotalk.exe", "KAKAOTALK.EXE"]
    
    for i, processName in processNames {
        mem := new _ClassMemory("ahk_exe " . processName)
        if (IsObject(mem)) {
            return true
        }
    }
    return false
}

; JSON 수집 메인 루프
CollectJSON:
    if (!isRunning || !IsObject(mem)) {
        return
    }
    
    ; 여러 위치에서 메시지 패턴 찾기
    addresses := FindAllMessagePatterns()
    
    newMessages := []
    for i, address in addresses {
        if (address <= 0) {
            continue
        }
        
        ; JSON 추출
        jsonData := ExtractPureJSON(address)
        if (!jsonData) {
            continue
        }
        
        ; 새 메시지인지 확인
        if (IsNewMessage(jsonData)) {
            ; sendAt 추출
            RegExMatch(jsonData, """sendAt"":(\d+)", sendAtMatch)
            sendAt := sendAtMatch1 ? sendAtMatch1 : 0
            
            ; 메시지 객체 생성
            msgObj := {sendAt: sendAt, json: jsonData}
            newMessages.Push(msgObj)
        }
    }
    
    ; 새 메시지가 있으면 버퍼에 추가하고 정렬 후 출력
    if (newMessages.Length() > 0) {
        for i, msg in newMessages {
            messageBuffer.Push(msg)
        }
        UpdateDisplay()
    }
return

; 모든 메시지 패턴 찾기
FindAllMessagePatterns() {
    addresses := []
    
    ; ,"message":" 패턴 생성
    pattern := mem.stringToPattern(",""message"":""")
    if (!IsObject(pattern)) {
        return addresses
    }
    
    ; 첫 번째 검색
    currentAddress := 0
    loop, 10 {  ; 최대 10개까지 찾기
        foundAddress := mem.processPatternScan(currentAddress, "", pattern*)
        if (foundAddress <= 0 || foundAddress <= currentAddress) {
            break
        }
        
        addresses.Push(foundAddress)
        currentAddress := foundAddress + 1
        
        ; 너무 많이 찾으면 중단
        if (A_Index >= 10) {
            break
        }
    }
    
    return addresses
}

; 메시지 패턴 찾기
FindMessagePattern() {
    ; ,"message":" 패턴 생성
    pattern := mem.stringToPattern(",""message"":""")
    if (!IsObject(pattern)) {
        return 0
    }
    
    ; 검색 시작 주소 (이전 주소 이후부터 검색)
    if (lastFoundAddress > 0) {
        startAddress := lastFoundAddress + 1  ; 이전 위치 다음부터
    } else {
        startAddress := 0
    }
    
    ; 먼저 이전 위치 이후에서 검색
    foundAddress := mem.processPatternScan(startAddress, "", pattern*)
    if (foundAddress > 0) {
        lastFoundAddress := foundAddress
        return foundAddress
    }
    
    ; 없으면 전체 메모리에서 다시 검색 (새로운 메시지가 앞쪽에 있을 수도)
    foundAddress := mem.processPatternScan(0, "", pattern*)
    if (foundAddress > 0 && foundAddress != lastFoundAddress) {
        lastFoundAddress := foundAddress
        return foundAddress
    }
    
    return 0
}

; 순수 JSON만 추출
ExtractPureJSON(baseAddress) {
    ; JSON 시작점 패턴
    startPattern := mem.stringToPattern("{""attachment""")
    if (!IsObject(startPattern)) {
        return ""
    }
    
    ; 시작점 검색
    if (baseAddress - 1024 > 0) {
        searchStart := baseAddress - 1024
    } else {
        searchStart := 0
    }
    
    jsonStart := 0
    loop, 5 {
        searchSize := baseAddress - searchStart + 100
        tempAddress := mem.addressPatternScan(searchStart, searchSize, startPattern*)
        
        if (tempAddress > 0 && tempAddress <= baseAddress) {
            jsonStart := tempAddress
            break
        }
        searchStart += 200
    }
    
    if (!jsonStart) {
        return ""
    }
    
    ; 큰 범위로 데이터 읽기
    maxLength := 4096
    rawData := mem.readString(jsonStart, maxLength, "UTF-8")
    if (!rawData) {
        return ""
    }
    
    ; JSON 끝점 찾기 - "type":숫자} 패턴
    endPos := RegExMatch(rawData, """type"":\d+}")
    if (endPos <= 0) {
        return ""
    }
    
    ; 정확한 끝점 계산
    RegExMatch(rawData, """type"":\d+}", endMatch, endPos)
    endPos += StrLen(endMatch) -1
    
    ; JSON 추출
    jsonData := SubStr(rawData, 1, endPos)
    
    ; JSON 시작점 정확히 맞추기
    startPos := InStr(jsonData, "{""attachment""")
    if (startPos > 0) {
        jsonData := SubStr(jsonData, startPos)
    }
    
    ; 불필요한 제어문자만 제거 (내용은 보존)
    jsonData := RegExReplace(jsonData, "[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "")
    
    ; 기본 JSON 구조 검증
    if (!InStr(jsonData, "{") || !InStr(jsonData, "}") || !InStr(jsonData, """msgId"":")) {
        return ""
    }
    
    return Trim(jsonData)
}

; 새 메시지인지 확인
IsNewMessage(jsonData) {
    ; msgId 추출
    RegExMatch(jsonData, """msgId"":(\d+)", msgIdMatch)
    msgId := msgIdMatch1
    
    if (!msgId) {
        ; msgId가 없으면 message 내용으로 중복 확인
        RegExMatch(jsonData, """message"":""([^""]*)", messageMatch)
        message := messageMatch1
        checkKey := "msg_" . message
    } else {
        checkKey := msgId
    }
    
    ; 중복 확인
    if (processedMessages.HasKey(checkKey)) {
        return false
    }
    
    ; 새 메시지 등록
    processedMessages[checkKey] := A_TickCount
    
    ; 메모리 정리 (30개 이상시)
    if (processedMessages.Count() > 30) {
        CleanupMessages()
    }
    
    return true
}

; 오래된 메시지 정리
CleanupMessages() {
    currentTime := A_TickCount
    toDelete := []
    
    for key, timestamp in processedMessages {
        ; 10초 이상 된 메시지 삭제 (더 빠른 정리)
        if (currentTime - timestamp > 10000) {
            toDelete.Push(key)
        }
    }
    
    for i, key in toDelete {
        processedMessages.Delete(key)
    }
}

; 화면 업데이트 (sendAt 기준 정렬)
UpdateDisplay() {
    ; sendAt 기준으로 정렬 (최신 메시지가 위로)
    SortMessageBuffer()
    
    ; Edit 컨트롤 내용 생성
    displayContent := ""
    
    ; 최대 50개 메시지만 표시
    maxDisplay := messageBuffer.Length() > 50 ? 50 : messageBuffer.Length()
    
    loop, %maxDisplay% {
        msg := messageBuffer[A_Index]
        
        ; Unix timestamp를 읽기 쉬운 시간으로 변환
        timeStr := FormatSendAtTime(msg.sendAt)
        
        displayContent .= msg.json . "`r`n"
    }
    
    ; Edit 컨트롤 업데이트
    GuiControl,, Output, %displayContent%
    
    ; 버퍼 크기 제한 (메모리 절약)
    if (messageBuffer.Length() > 100) {
        ; 오래된 메시지 제거
        newBuffer := []
        loop, 100 {
            if (A_Index <= messageBuffer.Length()) {
                newBuffer.Push(messageBuffer[A_Index])
            }
        }
        messageBuffer := newBuffer
    }
}

; sendAt 시간 포맷팅 함수
FormatSendAtTime(sendAtValue) {

    ahkTime := sendAtValue + 19700101000000

    
    ; 시간 포맷팅
    FormatTime, timeStr, %ahkTime%, yyyy-MM-dd HH:mm:ss

    
    return timeStr
}

; 메시지 버퍼 정렬 (sendAt 기준 내림차순)
SortMessageBuffer() {
    if (messageBuffer.Length() <= 1) {
        return
    }
    
    ; 간단한 버블 정렬 (sendAt 기준)
    loop, % messageBuffer.Length() - 1 {
        swapped := false
        loop, % messageBuffer.Length() - A_Index {
            ; sendAt 값이 없거나 0인 경우 가장 아래로 (오래된 것으로 처리)
            sendAt1 := messageBuffer[A_Index].sendAt ? messageBuffer[A_Index].sendAt : 0
            sendAt2 := messageBuffer[A_Index + 1].sendAt ? messageBuffer[A_Index + 1].sendAt : 0
            
            if (sendAt1 < sendAt2) {
                ; 위치 교환
                temp := messageBuffer[A_Index]
                messageBuffer[A_Index] := messageBuffer[A_Index + 1]
                messageBuffer[A_Index + 1] := temp
                swapped := true
            }
        }
        if (!swapped) {
            break
        }
    }
}

; 파일 저장 (sendAt 기준 정렬된 순서)
SaveToFile() {
    if (messageBuffer.Length() <= 0) {
        return
    }
    
    ; 파일 내용 생성
    fileContent := ""
    for i, msg in messageBuffer {
        ; sendAt 시간 포맷팅
        timeStr := FormatSendAtTime(msg.sendAt)
        fileContent .=  msg.json . "`n"
    }
    
    ; 파일 저장
    FileDelete, kakao_sorted.json
    FileAppend, %fileContent%, kakao_sorted.json
}

; GUI 종료
GuiClose:
ExitApp
