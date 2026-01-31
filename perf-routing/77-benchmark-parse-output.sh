#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/lib.sh"

need_cmd kubectl

# Output CSV file
OUTPUT_CSV="benchmark-latency-results.csv"
TEMP_DIR="/tmp/fortio-benchmark-$$"
mkdir -p "${TEMP_DIR}"

# Test configurations from the images
declare -a TEST_CONFIGS=(
  "50:500"
  "100:1000"
  "200:2000"
  "300:3000"
  "400:4000"
  "500:5000"
  "800:8000"
  "1000:10000"
)

# Gateways to test
GATEWAYS=("nginx" "envoy" "istio" "kong")

info "Starting benchmark for all gateways..."
info "Output will be saved to: ${OUTPUT_CSV}"

# Create CSV header
echo "Gateway,Concurrent,TPS,Duration,Latency_p99_ms" > "${OUTPUT_CSV}"

# Function to parse Fortio output and extract metrics
parse_fortio_output() {
  local output_file="$1"
  local gateway="$2"
  local concurrent="$3"
  local tps="$4"
  
  # Extract latency percentiles from Fortio output
  # Example output:
  # Sockets used: 50 (for perfect keepalive, would be 50)
  # Jitter: false
  # Code 200 : 30000 (100.0 %)
  # Response Header Sizes : count 30000 avg 230.5 +/- 0.5 min 230 max 231 sum 6915000
  # Response Body/Total Sizes : count 30000 avg 280.5 +/- 0.5 min 280 max 281 sum 8415000
  # All done 30000 calls (plus 0 warmup) 1.234 ms avg, 500.0 qps
  
  # Extract "All done" line for avg latency and actual QPS
  local all_done_line=$(grep "All done" "${output_file}" || echo "")
  local avg_ms=$(echo "${all_done_line}" | grep -oE '[0-9]+\.[0-9]+ ms avg' | grep -oE '[0-9]+\.[0-9]+' || echo "0")
  local actual_qps=$(echo "${all_done_line}" | grep -oE '[0-9]+\.[0-9]+ qps' | grep -oE '[0-9]+\.[0-9]+' || echo "0")
  local total_requests=$(echo "${all_done_line}" | grep -oE '[0-9]+ calls' | grep -oE '[0-9]+' || echo "0")
  
  # Extract percentiles from histogram section
  # Example from Fortio output:
  # # target 50% 0.001472
  # # target 75% 0.00243223
  # # target 90% 0.00298168
  # # target 99% 0.00398837
  # # target 99.9% 0.00612042
  # Format: # target 99% 0.00750115
  # Column $4 contains the value in seconds, convert to milliseconds
  
  local p50=$(grep "# target 50%" "${output_file}" 2>/dev/null | head -1 | awk '{if(NF>=4 && $4!="") print $4 * 1000; else print 0}')
  local p75=$(grep "# target 75%" "${output_file}" 2>/dev/null | head -1 | awk '{if(NF>=4 && $4!="") print $4 * 1000; else print 0}')
  local p90=$(grep "# target 90%" "${output_file}" 2>/dev/null | head -1 | awk '{if(NF>=4 && $4!="") print $4 * 1000; else print 0}')
  local p99=$(grep "# target 99%" "${output_file}" 2>/dev/null | head -1 | awk '{if(NF>=4 && $4!="") print $4 * 1000; else print 0}')
  local p999=$(grep "# target 99.9%" "${output_file}" 2>/dev/null | head -1 | awk '{if(NF>=4 && $4!="") print $4 * 1000; else print 0}')
  
  # Fallback to 0 if empty
  [[ -z "${p50}" ]] && p50="0"
  [[ -z "${p75}" ]] && p75="0"
  [[ -z "${p90}" ]] && p90="0"
  [[ -z "${p99}" ]] && p99="0"
  [[ -z "${p999}" ]] && p999="0"
  
  # Format p99 to 2 decimal places
  p99=$(printf "%.2f" "${p99}" 2>/dev/null || echo "0.00")
  
  # Write to CSV (only essential columns)
  echo "${gateway},${concurrent},${tps},60s,${p99}" >> "${OUTPUT_CSV}"
  
  info "  ✓ p99: ${p99}ms"
}

# Run benchmarks
for gateway in "${GATEWAYS[@]}"; do
  info ""
  info "=== Testing ${gateway} Gateway ==="
  
  for config in "${TEST_CONFIGS[@]}"; do
    IFS=':' read -r concurrent tps <<< "${config}"
    
    info "Running: concurrent=${concurrent}, tps=${tps}"
    
    # Output file for this test
    OUTPUT_FILE="${TEMP_DIR}/${gateway}-${concurrent}-${tps}.txt"
    
    # Run Fortio load test via the existing script
    bash "${SCRIPT_DIR}/55-loadtest-fortio-rust.sh" "${gateway}" "60s" "${concurrent}" "${tps}" > "${OUTPUT_FILE}" 2>&1 || {
      warn "Test failed for ${gateway} ${concurrent}/${tps}"
      # Write N/A values
      echo "${gateway},${concurrent},${tps},60s,N/A" >> "${OUTPUT_CSV}"
      continue
    }
    
    # Parse the output
    parse_fortio_output "${OUTPUT_FILE}" "${gateway}" "${concurrent}" "${tps}"
    
    # Wait between tests to let system stabilize
    sleep 10
  done
  
  info "Completed ${gateway} gateway"
done

# Cleanup temp files
rm -rf "${TEMP_DIR}"

info ""
info "=== Benchmark Completed ==="
info "Results saved to: ${OUTPUT_CSV}"
info ""
info "To view results in table format:"
info "  column -t -s, ${OUTPUT_CSV} | less -S"
info ""
info "To copy to clipboard (macOS):"
info "  cat ${OUTPUT_CSV} | pbcopy"
info ""
info "To import to Excel/Google Sheets:"
info "  Open the CSV file directly"
