# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Benchmark tool for measuring the performance impact of IDS traffic mirroring
# under normal/flood network conditions.
#
# Interleaves Mirror ON and Mirror OFF measurements in short windows to cancel
# out slow-varying conditions (WiFi fading, thermal, background load).
#
# Run on net-vm as root:
#   sudo ids-mirror-bench [--iface IFACE] [--window SEC] [--iterations N] [--iperf-server HOST]
#
{
  pkgs,
  ...
}:
pkgs.writeShellApplication {
  name = "ids-mirror-bench";
  runtimeInputs = [
    pkgs.iproute2
    pkgs.iputils
    pkgs.iperf3
    pkgs.gawk
    pkgs.openssh
    pkgs.gnuplot
  ];
  text = ''
    IFACE=""
    WINDOW=30
    ITERATIONS=10
    IPERF_SERVER=""
    IPERF_MSS=""
    IPERF_BW=""
    HOST_SSH=""
    FLOOD=0
    SWEEP=0
    SWEEP_MIN=""
    SWEEP_MAX=""
    SWEEP_STEP="5M"
    NETEM=""

    TARGETS=(
      "8.8.8.8"
      "1.1.1.1"
      "9.9.9.9"
      "208.67.222.222"
    )

    usage() {
      echo "Usage: ids-mirror-bench [OPTIONS]"
      echo "  --iface         Physical NIC to monitor (auto-detected if not set)"
      echo "  --window        Measurement window per ON/OFF slot in sec (default: 30)"
      echo "  --iterations    Number of ON/OFF pairs (default: 10)"
      echo "  --targets       Comma-separated IPs/hosts"
      echo "  --iperf-server  iperf3 server host/IP (optional, runs at full speed)"
      echo "  --bandwidth     iperf3 target bandwidth (e.g. 100M, 500M; default: unlimited)"
      echo "  --mss           TCP MSS for iperf3 (default: OS default ~1460; use e.g. 512 to send small packets)"
      echo "  --host-ssh      SSH target for host CPU measurement (e.g. ghaf@192.168.100.1)"
      echo "  --flood         Use flood ping instead of normal rate"
      echo "  --sweep         Sweep bandwidth from MIN to MAX and plot CPU overhead vs BW"
      echo "  --sweep-min     Lower bandwidth limit for sweep (default: same as step)"
      echo "  --sweep-max     Upper bandwidth limit for sweep (e.g. 900M)"
      echo "  --sweep-step    Bandwidth step size (default: 5M)"
      echo "  --netem         Override netem params (e.g. \"slot 30ms 50ms packets 1024 limit 4096\")"
      exit 0
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --iface)        IFACE="$2";        shift 2 ;;
        --window)       WINDOW="$2";       shift 2 ;;
        --iterations)   ITERATIONS="$2";   shift 2 ;;
        --iperf-server) IPERF_SERVER="''${2//[[:space:]]/}"; shift 2 ;;
        --bandwidth)    IPERF_BW="$2";     shift 2 ;;
        --mss)          IPERF_MSS="$2";    shift 2 ;;
        --host-ssh)     HOST_SSH="$2";     shift 2 ;;
        --flood)        FLOOD=1;           shift ;;
        --sweep)        SWEEP=1;           shift ;;
        --sweep-min)    SWEEP_MIN="$2";    shift 2 ;;
        --sweep-max)    SWEEP_MAX="$2";    shift 2 ;;
        --sweep-step)   SWEEP_STEP="$2";   shift 2 ;;
        --netem)        NETEM="$2";        shift 2 ;;
        --targets)
          IFS=',' read -ra TARGETS <<< "$2"
          shift 2
          ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
      esac
    done

    if [[ -z "$IFACE" ]]; then
      for sysfs in /sys/class/net/*; do
        name=$(basename "$sysfs")
        [ -e "$sysfs/device" ] || continue
        [[ "$name" == "mirror" ]] && continue
        driver=$(basename "$(readlink "$sysfs/device/driver")" 2>/dev/null) || true
        [ "$driver" = "virtio_net" ] && continue
        IFACE="$name"
        break
      done
      [[ -n "$IFACE" ]] || { echo "ids-mirror-bench: no physical NIC found; use --iface"; exit 1; }
    fi

    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    ping_target() {
      local target="$1"
      local out="$2/ping_$target"
      if [[ "$FLOOD" -eq 1 ]]; then
        ping -f -w "$WINDOW" -s 1400 -q "$target" > /dev/null 2>&1 || true
        printf "N/A N/A N/A N/A N/A\n" > "$out"
      else
        local count=$(( WINDOW * 5 ))
        ping -c "$count" -i 0.2 -q "$target" 2>/dev/null \
          | awk '
            /packet loss/ { for (i=1;i<=NF;i++) if ($i~/^[0-9]+%$/) { drop=$i+0; break } }
            /^rtt/ { split($4,r,"/"); avg=r[2] }
            END { printf "%.2f %.2f\n", drop+0, avg+0 }
          ' > "$out"
      fi
    }

    apply_netem() {
      [[ -z "$NETEM" ]] && return
      tc qdisc del dev mirror root 2>/dev/null || true
      # shellcheck disable=SC2086
      tc qdisc add dev mirror root netem $NETEM
    }

    # Run one measurement window, append results to accumulator files in $ACCDIR
    measure_window() {
      local accdir="$1" slot="$TMPDIR/slot"
      mkdir -p "$slot"

      local cpu_idle_before cpu_total_before rx_before tx_before mem_before mirror_rx_before
      read -r cpu_idle_before cpu_total_before < <(awk '/^cpu /{idle=$5;s=0;for(i=2;i<=NF;i++)s+=$i;print idle,s;exit}' /proc/stat)
      rx_before=$(awk -v d="$IFACE:" '$1==d{print $2}' /proc/net/dev)
      tx_before=$(awk -v d="$IFACE:" '$1==d{print $10}' /proc/net/dev)
      mem_before=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{print t-a}' /proc/meminfo)
      mirror_rx_before=$(awk -v d="mirror:" '$1==d{print $10}' /proc/net/dev 2>/dev/null || echo 0)

      local pids=()
      for target in "''${TARGETS[@]}"; do
        ping_target "$target" "$slot" &
        pids+=($!)
      done

      local iperf_bw="N/A" iperf_retr="N/A"
      if [[ -n "$IPERF_SERVER" ]]; then
        local mss_arg="" bw_arg=""
        [[ -n "$IPERF_MSS" ]] && mss_arg="-M $IPERF_MSS"
        [[ -n "$IPERF_BW"  ]] && bw_arg="-b $IPERF_BW"
        # shellcheck disable=SC2086
        iperf3 -c "$IPERF_SERVER" -t "$WINDOW" $mss_arg $bw_arg \
          | awk '/sender/{print $7,$9}' > "$slot/iperf" &
        pids+=($!)
      fi

      # Collect host CPU in parallel via SSH
      if [[ -n "$HOST_SSH" ]]; then
        (
          ssh -o BatchMode=yes -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$HOST_SSH" \
            "b=\$(awk '/^cpu /{print \$5,\$2+\$3+\$4+\$5+\$6+\$7+\$8}' /proc/stat); \
             sleep $WINDOW; \
             a=\$(awk '/^cpu /{print \$5,\$2+\$3+\$4+\$5+\$6+\$7+\$8}' /proc/stat); \
             awk -v b=\"\$b\" -v a=\"\$a\" 'BEGIN{
               split(b,B,\" \"); split(a,A,\" \")
               idle=A[1]-B[1]; total=A[2]-B[2]
               printf \"%.2f\n\",(total>0)?(1-idle/total)*100:0
             }'" > "$slot/host_cpu" 2>/dev/null \
          || echo "  [warn] host SSH unreachable (''${HOST_SSH})" >&2
        ) &
        pids+=($!)
      fi

      for pid in "''${pids[@]}"; do wait "$pid" || true; done

      local cpu_idle_after cpu_total_after rx_after tx_after mem_after mirror_rx_after
      read -r cpu_idle_after cpu_total_after < <(awk '/^cpu /{idle=$5;s=0;for(i=2;i<=NF;i++)s+=$i;print idle,s;exit}' /proc/stat)
      rx_after=$(awk -v d="$IFACE:" '$1==d{print $2}' /proc/net/dev)
      tx_after=$(awk -v d="$IFACE:" '$1==d{print $10}' /proc/net/dev)
      mem_after=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{print t-a}' /proc/meminfo)
      mirror_rx_after=$(awk -v d="mirror:" '$1==d{print $10}' /proc/net/dev 2>/dev/null || echo 0)

      local cpu_pct tx_mbps rx_mbps mem_mb mem_delta_mb mirror_mbps
      cpu_pct=$(awk "BEGIN{idle=$cpu_idle_after-$cpu_idle_before;total=$cpu_total_after-$cpu_total_before;printf\"%.2f\",(total>0)?(1-idle/total)*100:0}")
      tx_mbps=$(awk "BEGIN{printf\"%.2f\",($tx_after-$tx_before)*8/$WINDOW/1000000}")
      rx_mbps=$(awk "BEGIN{printf\"%.2f\",($rx_after-$rx_before)*8/$WINDOW/1000000}")
      mem_mb=$(awk "BEGIN{printf\"%.1f\",$mem_after/1024}")
      mem_delta_mb=$(awk "BEGIN{printf\"%+.1f\",($mem_after-$mem_before)/1024}")
      mirror_mbps=$(awk "BEGIN{printf\"%.2f\",($mirror_rx_after-$mirror_rx_before)*8/$WINDOW/1000000}")

      if [[ -n "$IPERF_SERVER" && -s "$slot/iperf" ]]; then
        read -r iperf_bw iperf_retr < "$slot/iperf"
      fi

      # Aggregate ping stats
      local agg_loss="N/A" agg_lat="N/A"
      if [[ "$FLOOD" -eq 0 ]] && ls "$slot"/ping_* &>/dev/null; then
        read -r agg_loss agg_lat < <(
          awk '{loss+=$1;lat+=$2;n++} END{printf"%.1f %.2f\n",loss/n,lat/n}' "$slot"/ping_*
        )
      fi

      echo "$cpu_pct"                          >> "$accdir/cpu"
      [[ -s "$slot/host_cpu" ]] && cat "$slot/host_cpu" >> "$accdir/host_cpu"
      echo "$tx_mbps"      >> "$accdir/tx"
      echo "$rx_mbps"      >> "$accdir/rx"
      echo "$mirror_mbps"  >> "$accdir/mirror_rx"
      echo "$mem_mb"       >> "$accdir/mem"
      echo "$mem_delta_mb" >> "$accdir/mem_delta"
      echo "$iperf_bw"     >> "$accdir/iperf_bw"
      echo "$iperf_retr"   >> "$accdir/iperf_retr"
      echo "$agg_loss"     >> "$accdir/loss"
      echo "$agg_lat"      >> "$accdir/lat"

      rm -rf "$slot"
    }

    # Compute mean ± stddev from a file of numbers (skip non-numeric lines)
    stats() {
      [[ -f "$1" ]] || { echo "N/A"; return; }
      awk 'BEGIN{n=0;s=0;s2=0}
           /^[0-9]/{n++;s+=$1;s2+=$1*$1}
           END{
             if(n==0){print "N/A"; exit}
             mean=s/n
             std=(n>1)?sqrt((s2-s*s/n)/(n-1)):0
             printf "%.2f ± %.2f", mean, std
           }' "$1"
    }

    delta() {
      [[ -f "$1" && -f "$2" ]] || { echo "N/A"; return; }
      awk 'NR==FNR{a[NR]=$1;next}
           FNR in a && /^[0-9]/{diff+=($1-a[FNR]);n++}
           END{if(n>0)printf"%+.2f",diff/n;else print"N/A"}' "$1" "$2"
    }

    # Mean value only (no ±stddev) — for numeric use in sweep dat file
    mean_val() {
      [[ -f "$1" ]] || { echo "0"; return; }
      awk '/^[0-9]/{n++;s+=$1} END{if(n>0)printf"%.2f",s/n;else print"0"}' "$1"
    }

    # Parse bandwidth string (e.g. "5M", "200M", "1G") → Mbps as float
    bw_to_mbps() {
      awk -v v="$1" 'BEGIN{
        n=v+0; u=substr(v,length(v))
        if(u=="G"||u=="g") printf "%.2f", n*1000
        else if(u=="K"||u=="k") printf "%.2f", n/1000
        else printf "%.2f", n
      }'
    }

    # Bandwidth sweep mode
    if [[ "$SWEEP" -eq 1 ]]; then
      [[ -n "$IPERF_SERVER" ]] || { echo "ids-mirror-bench: --sweep requires --iperf-server"; exit 1; }
      [[ -n "$SWEEP_MAX"   ]] || { echo "ids-mirror-bench: --sweep requires --sweep-max";    exit 1; }

      printf "  checking iperf3 server %s... " "$IPERF_SERVER"
      for _try in 1 2 3; do
        if iperf3 -c "$IPERF_SERVER" -t 1 -b 1M >/dev/null 2>&1; then
          printf "ok\n\n"
          break
        fi
        if [[ "$_try" -eq 3 ]]; then
          printf "FAILED\n"
          echo "ids-mirror-bench: cannot reach iperf3 server $IPERF_SERVER — details:" >&2
          iperf3 -c "$IPERF_SERVER" -t 1 -b 1M >&2 || true
          exit 1
        fi
        printf "retry... "
        sleep 2
      done

      max_mbps=$(bw_to_mbps "$SWEEP_MAX")
      step_mbps=$(bw_to_mbps "$SWEEP_STEP")
      min_mbps=$(bw_to_mbps "''${SWEEP_MIN:-$SWEEP_STEP}")
      SWEEP_DAT="$TMPDIR/sweep.dat"

      echo "========================================================"
      echo "  IDS Mirror BW Sweep  (''${SWEEP_MIN:-$SWEEP_STEP} → $SWEEP_MAX, step $SWEEP_STEP)"
      echo "  iperf3 server : $IPERF_SERVER"
      echo "  Iterations    : $ITERATIONS × ''${WINDOW}s per step"
      echo "========================================================"
      echo ""

      # Warmup — discarded; stabilises page cache, iperf connections, CPU state
      printf "  warmup...\n"
      IPERF_BW="''${SWEEP_MIN:-$SWEEP_STEP}"
      wD="$TMPDIR/warmup"; mkdir -p "$wD"
      systemctl start ids-mirror 2>/dev/null || true; apply_netem; sleep 1
      measure_window "$wD"
      systemctl stop  ids-mirror 2>/dev/null || true; sleep 1
      measure_window "$wD"
      rm -rf "$wD"
      echo ""

      bw_mbps="$min_mbps"
      while awk "BEGIN{exit !($bw_mbps <= $max_mbps)}"; do
        bw_label="''${bw_mbps%.*}M"
        IPERF_BW="$bw_label"
        sON="$TMPDIR/sw_on"; sOFF="$TMPDIR/sw_off"
        mkdir -p "$sON" "$sOFF"

        printf "  %-8s  measuring...\n" "$bw_label"
        for i in $(seq 1 "$ITERATIONS"); do
          systemctl start ids-mirror 2>/dev/null || true; apply_netem; sleep 1
          measure_window "$sON"
          systemctl stop  ids-mirror 2>/dev/null || true; sleep 1
          measure_window "$sOFF"
        done
        systemctl start ids-mirror 2>/dev/null || true; apply_netem

        cpu_d=$(delta "$sOFF/cpu" "$sON/cpu")
        ram_d=$(delta "$sOFF/mem" "$sON/mem")
        iperf_on=$(mean_val "$sON/iperf_bw")
        iperf_off=$(mean_val "$sOFF/iperf_bw")
        printf "            cpu_delta=%-8s  ram_delta=%-8s  iperf_ON=%-8s  iperf_OFF=%s Mbps\n" \
          "$cpu_d" "$ram_d" "$iperf_on" "$iperf_off"
        awk -v bw="$bw_mbps" -v cpu="$cpu_d" -v ram="$ram_d" \
            -v ion="$iperf_on" -v ioff="$iperf_off" \
          'BEGIN{
            c=cpu+0; r=ram+0; on=ion+0; off=ioff+0
            penalty=(off>0) ? (off-on)/off*100 : 0
            printf "%s %.2f %.2f %.2f %.2f %.2f\n", bw, \
              (c<0)?0:c, (r<0)?0:r, on, off, (penalty<0)?0:penalty
          }' >> "$SWEEP_DAT"
        rm -rf "$sON" "$sOFF"

        bw_mbps=$(awk "BEGIN{printf \"%.2f\", $bw_mbps + $step_mbps}")
      done

      _gplot_single() {
        local title="$1" ylabel="$2" col="$3" color="$4"
        echo ""
        echo "  $title"
        echo "  $(echo "$title" | tr '[:print:]' '-')"
        gnuplot -e "
          set terminal dumb ansi size 110 22;
          set title '$title  [$ylabel]';
          set xlabel 'Bandwidth (Mbps)';
          set key off;
          set yrange [0:*];
          set grid;
          set style fill solid 0.8;
          set boxwidth $step_mbps*0.7;
          set style line 1 lc rgb '$color';
          plot '$SWEEP_DAT' using 1:$col with boxes ls 1
        "
      }

      _gplot_single "CPU Overhead vs Bandwidth"  "CPU delta (%)"   2 "#FF4444"
      _gplot_single "RAM Overhead vs Bandwidth"   "RAM delta (MiB)" 3 "#4488FF"

      max_penalty=$(awk 'BEGIN{m=0} /^[0-9]/{if($6+0>m)m=$6+0} END{printf "%.4f",m}' "$SWEEP_DAT")
      echo ""
      echo "  iperf3 Throughput Penalty vs Bandwidth"
      echo "  --------------------------------------"
      if awk "BEGIN{exit !($max_penalty < 0.05)}"; then
        echo "  (max penalty ''${max_penalty}% — below 0.05% threshold, no measurable throughput impact)"
      else
        gnuplot -e "
          set terminal dumb ansi size 110 22;
          set title 'iperf3 Throughput Penalty vs Bandwidth  [BW penalty %]';
          set xlabel 'Bandwidth (Mbps)';
          set key off;
          set yrange [0:*];
          set grid;
          set style fill solid 0.8;
          set boxwidth $step_mbps*0.7;
          set style line 1 lc rgb '#44BB44';
          plot '$SWEEP_DAT' using 1:6 with boxes ls 1
        "
      fi

      echo ""
      exit 0
    fi

    if [[ -n "$IPERF_SERVER" ]]; then
      printf "  checking iperf3 server %s... " "$IPERF_SERVER"
      for _try in 1 2 3; do
        if iperf3 -c "$IPERF_SERVER" -t 1 -b 1M >/dev/null 2>&1; then
          printf "ok\n"
          break
        fi
        if [[ "$_try" -eq 3 ]]; then
          printf "FAILED\n"
          echo "ids-mirror-bench: cannot reach iperf3 server $IPERF_SERVER — details:" >&2
          iperf3 -c "$IPERF_SERVER" -t 1 -b 1M >&2 || true
          exit 1
        fi
        printf "retry... "
        sleep 2
      done
    fi

    if [[ "$FLOOD" -eq 1 ]]; then
      MODE_DESC="flood (1400-byte, max rate)"
    else
      MODE_DESC="normal (64-byte, 5 pkt/s)"
    fi

    TOTAL=$(( ITERATIONS * 2 * WINDOW ))
    echo "========================================================"
    echo "  IDS Mirror Overhead Benchmark"
    echo "  Interface  : $IFACE"
    echo "  Mode       : $MODE_DESC"
    echo "  Window     : ''${WINDOW}s × ''${ITERATIONS} pairs = ''${TOTAL}s total"
    [[ -n "$IPERF_SERVER" ]] && echo "  iperf3     : $IPERF_SERVER  MSS=''${IPERF_MSS:-default}  BW=''${IPERF_BW:-unlimited}"
    [[ -n "$HOST_SSH"    ]] && echo "  host SSH   : $HOST_SSH"
    echo "========================================================"
    echo ""

    ON_DIR="$TMPDIR/on"
    OFF_DIR="$TMPDIR/off"
    mkdir -p "$ON_DIR" "$OFF_DIR"

    for i in $(seq 1 "$ITERATIONS"); do
      echo "  Pair $i/$ITERATIONS — Mirror ON..."
      systemctl start ids-mirror 2>/dev/null || true
      apply_netem
      sleep 1
      measure_window "$ON_DIR"

      echo "  Pair $i/$ITERATIONS — Mirror OFF..."
      systemctl stop ids-mirror 2>/dev/null || true
      sleep 1
      measure_window "$OFF_DIR"
    done

    systemctl start ids-mirror 2>/dev/null || true

    echo ""
    echo "========================================================"
    echo "  Results (mean ± stddev over $ITERATIONS pairs)"
    echo "========================================================"
    printf "  %-28s  %-20s  %-20s  %s\n" "Metric" "Mirror ON" "Mirror OFF" "Delta"
    printf "  %-28s  %-20s  %-20s  %s\n" "------" "---------" "----------" "-----"
    printf "  %-28s  %-20s  %-20s  %s\n" \
      "CPU usage / net-vm (%):" \
      "$(stats "$ON_DIR/cpu")" \
      "$(stats "$OFF_DIR/cpu")" \
      "$(delta "$OFF_DIR/cpu" "$ON_DIR/cpu")%"
    if [[ -n "$HOST_SSH" ]]; then
      printf "  %-28s  %-20s  %-20s  %s\n" \
        "CPU usage / host (%):" \
        "$(stats "$ON_DIR/host_cpu")" \
        "$(stats "$OFF_DIR/host_cpu")" \
        "$(delta "$OFF_DIR/host_cpu" "$ON_DIR/host_cpu")%"
    fi
    printf "  %-28s  %-20s  %-20s  %s\n" \
      "TX throughput (Mbps):" \
      "$(stats "$ON_DIR/tx")" \
      "$(stats "$OFF_DIR/tx")" \
      "$(delta "$OFF_DIR/tx" "$ON_DIR/tx") Mbps"
    if [[ "$FLOOD" -eq 0 ]]; then
      printf "  %-28s  %-20s  %-20s  %s\n" \
        "Latency avg (ms):" \
        "$(stats "$ON_DIR/lat")" \
        "$(stats "$OFF_DIR/lat")" \
        "$(delta "$OFF_DIR/lat" "$ON_DIR/lat") ms"
      printf "  %-28s  %-20s  %-20s\n" \
        "Packet loss (%):" \
        "$(stats "$ON_DIR/loss")" \
        "$(stats "$OFF_DIR/loss")"
    fi
    printf "  %-28s  %-20s  %-20s  %s\n" \
      "RAM used (MiB):" \
      "$(stats "$ON_DIR/mem")" \
      "$(stats "$OFF_DIR/mem")" \
      "$(delta "$OFF_DIR/mem" "$ON_DIR/mem") MiB"
    if [[ -n "$IPERF_SERVER" ]]; then
      printf "  %-28s  %-20s  %-20s  %s\n" \
        "iperf3 BW (Mbps):" \
        "$(stats "$ON_DIR/iperf_bw")" \
        "$(stats "$OFF_DIR/iperf_bw")" \
        "$(delta "$OFF_DIR/iperf_bw" "$ON_DIR/iperf_bw") Mbps"
    fi
    printf "  %-28s  %s\n" \
      "Mirror tap TX (info, Mbps):" \
      "$(stats "$ON_DIR/mirror_rx")"
    echo ""
  '';
}
