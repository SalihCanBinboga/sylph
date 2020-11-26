#!/bin/bash
echo 'Running Script'
set -e

main() {
  case $1 in
    --help)
        show_help
        ;;
    --run-test)
        if [[ -z $2 ]]; then show_help; fi
        custom_test_runner "$2"
        ;;
    --run-tests)
        if [[ -z $2 ]]; then show_help; fi
        run_tests "$2"
		echo "Main Çalıştı: $2"
        ;;
    --run-driver)
        if [[ -z $2 ]]; then show_help; fi
        run_no_build "$2"
        ;;
    --get-appid)
        if [[ -z $2 ]]; then show_help; fi
        getAppIdFromApk "$2"
        ;;
    *)
        show_help
        ;;
  esac
}

show_help() {
    printf "\n\nusage: %s [--help] [--run-test <test path>] [--run-driver <test main path>] [--run-tests <comma-delimited list of test paths>]

Utility for running integration tests for pre-installed flutter app on android device.
(app must be built in debug mode with 'enableFlutterDriverExtension()')

where:
    --run-test <test path>
        run test from dart using a custom setup (similar to --no-build)
        <test path>
            path of test to run, eg, test_driver/main_test.dart
    --run-tests <array of test paths>
        run tests from dart using a custom setup (similar to --no-build)
        <comma-delimited list of test paths>
            list of test paths (eg, 'test_driver/main_test1.dart,test_driver/main_test2.dart')
    --run-driver
        run test using driver --no-build
        <test main path>
            path to test main, eg, test_driver/main.dart
" "$(basename "$0")"
    exit 1
}

run_tests() {
  local test_paths=$1
  echo "Test Paths :$1"

  while IFS=',' read -ra tests; do
    for test in "${tests[@]}"; do
        custom_test_runner "$test"
    done
  done <<< "$test_paths"
}

custom_test_runner() {
    local test_path=$1
    local forwarded_port=4723
	echo "test_path: $test_path"

    local app_id
    app_id=$(grep applicationId android/app/build.gradle | awk '{print $2}' | tr -d '"')

    echo "Starting Flutter app $app_id in debug mode..."

    flutter pub get

    adb version
	
    adb shell am force-stop "$app_id"
	
    adb logcat -c
	
    adb shell am start -a android.intent.action.RUN -f 0x20000000 --ez enable-background-compilation true --ez enable-dart-profiling true --ez enable-checked-mode true --ez verify-entry-points true --ez start-paused true "$app_id/.MainActivity"
	
    obs_str=$( (adb logcat -v time &) | grep -m 1 "Observatory listening on")
    obs_port_str=$(echo "$obs_str" | grep -Eo '[^:]*$')
    obs_port=$(echo "$obs_port_str" | grep -Eo '^[0-9]+')
    obs_token=$(echo "$obs_port_str" | grep -Eo '\/.*\/$')
    echo Observatory on port "$obs_port"
	
    port_forwarded=$(adb forward --list| grep ${forwarded_port}) || true
    if [[ ! "$port_forwarded" == "" ]]; then
      echo "unforwarding ${forwarded_port}"
      adb forward --remove tcp:${forwarded_port}
    fi
	
    if [[ ! "$USERNAME" == 'device-farm' ]]; then
      forwarded_port=$(adb forward tcp:0 tcp:"$obs_port")
    else
      adb forward tcp:"$forwarded_port" tcp:"$obs_port"
    fi
    echo Local port "$forwarded_port" forwarded to observatory port "$obs_port"
	
    echo "Running integration test $test_path on app $app_id ..."
    export VM_SERVICE_URL=http://127.0.0.1:"$forwarded_port$obs_token"
    dart "$test_path"
}

getAppIdFromApk() {
  local apk_path="$1"
  
  local re="L.*/MainActivity.*;"
  local se="s:L\(.*\)/MainActivity;:\1:p"
  local te=" / .";

  local app_id
  app_id="$(unzip -p "$apk_path" classes.dex | strings | grep -Eo "$re" | sed -n -e "$se" | tr "$te")"

  echo "$app_id"
}

run_no_build() {
  local test_main="$1"
  
  flutter config --no-analytics
  flutter packages get
  echo "Running flutter --verbose drive --no-build $test_main"
  
  flutter drive --verbose --no-build "$test_main"
}

main "$@"
