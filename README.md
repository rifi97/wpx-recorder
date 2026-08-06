# WPX 데이터 기록기

macOS용 WPX 데이터 수신 및 CSV 기록 앱입니다. WPX-01 계열의 확인된 `0x0001` 측정 프레임을 읽어 온도 5종, 전압, 전류, 계산 전력, 주파수, RPP, 동작 모드, 누적값을 저장합니다.

## 사용 방법

1. 기존 WPX 공식 앱을 종료합니다. 시리얼 포트는 한 번에 한 앱에서만 사용할 수 있습니다.
2. `outputs/WPXRecorder.app`을 실행합니다.
3. 장치 포트를 선택하고 기록 시간을 분 단위로 입력합니다.
4. 필요하면 저장 폴더를 선택한 뒤 `기록 시작`을 누릅니다.
5. 설정한 시간이 지나면 자동으로 중지되고 CSV가 저장됩니다. `기록 중지`로 일찍 끝낼 수도 있습니다.

기본 저장 폴더는 `~/Documents/WPX Records`이며 파일명은 `WPX_YYYYMMDD_HHMMSS.csv` 형식입니다.

## CSV 주요 컬럼

`timestamp`, `elapsed_s`, `vrect_v`, `vout_v`, `current_a`, `power_w`, `frequency_hz`, `core_temp_c`, `eload_temp_c`, `ext_probe_temp_c`, `bridge_temp_c`, `coil_temp_c` 등이 포함됩니다.

이 앱은 장치에 명령을 보내지 않고 수신 데이터만 처리합니다. 현재 연결된 장치에서 확인된 외부 Probe 값이 0이면 센서 미연결 또는 비활성 상태일 수 있습니다.
