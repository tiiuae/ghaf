#!/bin/bash

# Start OPA server in background once
opa run --server --watch ../../default-policy &> /dev/null &
OPA_PID=$!

# Wait for OPA server to be ready
#
for i in {1..10}; do
  if curl -s localhost:8181/health > /dev/null; then
    break
  fi

  if [ "$i" -lt 10 ]; then
    printf "\r\033[KWaiting for OPA server... (%d)" "$i"
    sleep 1
  else
    printf "\r\033[KTimeout! No response from OPA server.\n"
    exit 1
  fi
done
printf "\r\033[K"
# Function to run one test
run_test() {
  local test_name="$1"
  local input_json="$2"
  local expected_output="$3"

  local response
  response=$(curl -s -X POST localhost:8181/v1/data/usb_hotplug/allowed_vms \
    -H "Content-Type: application/json" \
    -d "$input_json")

  # Strip whitespace for comparison
  local response_clean expected_clean
  response_clean=$(echo "$response" | tr -d '[:space:]')
  expected_clean=$(echo "$expected_output" | tr -d '[:space:]')

  if [[ "$response_clean" == "$expected_clean" ]]; then
    result="✅ PASS"
  else
    result="❌ FAIL"
  fi

  printf "%-6s expected: %-30s received: %-30s Result: %s\n" \
    "$test_name" "$expected_output" "$response" "$result"
}

run_test "TEST1" '{"input":{"vendor_id":"0x0b95","product_id":"0x1790","class":"0xff","subclass":"0x01","protocol":"0x00"}}' '{"result":["net-vm"]}'

run_test "TEST2" '{"input":{"vendor_id":"0xdead","product_id":"0xbeef","class":"0x01","subclass":"0x02","protocol":"0x01"}}' '{"result":["audio-vm"]}'

run_test "TEST3" '{"input":{"vendor_id":"0x04f2","product_id":"0xb751","class":"0x0e","subclass":"0x02","protocol":"0x01"}}' '{"result":["chrome-vm"]}'

run_test "TEST4" '{"input":{"vendor_id":"0x04f2","product_id":"0xb755","class":"0x0e","subclass":"0x02","protocol":"0x01"}}' '{"result":["chrome-vm"]}'

run_test "TEST5" '{"input":{"vendor_id":"0x04f2","product_id":"0xb755","class":"0xe0","subclass":"0x01","protocol":"0x01"}}' '{"result":[]}'

run_test "TEST6" '{"input":{"vendor_id":"0xbadb","product_id":"0xdada","class":"0xe0","subclass":"0x01","protocol":"0x01"}}' '{"result":[]}'

run_test "TEST7" '{"input":{"vendor_id":"0xbabb","product_id":"0xcaca","class":"0xe0","subclass":"0x01","protocol":"0x01"}}' '{"result":[]}'

run_test "TEST8" '{"input":{"vendor_id":"0xbabb","product_id":"0xb755","class":"0xe0","subclass":"0x01","protocol":"0x01"}}' '{"result":[]}'


# Kill OPA server after tests
kill $OPA_PID

