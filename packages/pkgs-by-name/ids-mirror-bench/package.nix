# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Benchmarks IDS traffic mirroring overhead. Interleaves Mirror ON/OFF windows
# to cancel out slow-varying conditions (WiFi fading, thermal, background load).
#
#   ab mode (default)                    sweep mode (--sweep)
#   ------------------                   --------------------
#   ON  --measure--> on[i]               for bw in min..max step step_mbps:
#   OFF --measure--> off[i]                ON  --measure--> on[i]
#   } x ITERATIONS pairs                   OFF --measure--> off[i]
#   delta = mean(off) - mean(on)         } x ITERATIONS pairs, per bw step
#                                         delta(bw) -> sweep.dat -> gnuplot
#
#   workstation          net-vm (this script, root)     ghaf-host
#   -----------          --------------------------     ---------
#   iperf3 -s  <-------- iperf3 -c
#                        ids-mirror-bench --nc :9999--> ids-bench-server
#                        tc mirred -> mirror tap ------> host relay -> ids-vm
#
# ids-bench-server: host-side CPU sampler, queried over nc. Protocol:
#   echo "cpu 10" | nc <host-ip> 9999   # CPU% averaged over 10s
#   echo "hostname" | nc <host-ip> 9999
#   echo "irqbalance" | nc <host-ip> 9999
{
  pkgs,
  ...
}:
let
  # ships on net-vm (systemPackages), run as root over ssh
  bench = pkgs.writeShellApplication {
    name = "ids-mirror-bench";
    runtimeInputs = with pkgs; [
      iproute2
      iputils
      iperf3
      gawk
      openssh
      gnuplot
    ];
    text = ''
      err() {
        if [[ $# -gt 1 ]]; then
          local fmt="$1"
          shift
          # shellcheck disable=SC2059
          printf "ids-mirror-bench: ''${fmt}\n" "$@" >&2
        else
          printf 'ids-mirror-bench: %s\n' "$1" >&2
        fi
      }

      info() {
        if [[ $# -gt 1 ]]; then
          local fmt="$1"
          shift
          # shellcheck disable=SC2059
          printf "  [info] ''${fmt}\n" "$@"
        else
          printf '  [info] %s\n' "$1"
        fi
      }

      warn() {
        if [[ $# -gt 1 ]]; then
          local fmt="$1"
          shift
          # shellcheck disable=SC2059
          printf "  [warn] ''${fmt}\n" "$@" >&2
        else
          printf '  [warn] %s\n' "$1" >&2
        fi
      }

      report() {
        local title="$1"
        shift
        echo "========================================================"
        echo "  $title"
        local pair label maxlen=0
        for pair in "$@"; do
          label="''${pair%%|*}"
          [[ ''${#label} -gt $maxlen ]] && maxlen=''${#label}
        done
        for pair in "$@"; do
          printf "  %-''${maxlen}s : %s\n" "''${pair%%|*}" "''${pair#*|}"
        done
        echo "========================================================"
      }

      IFACE=""
      WINDOW=30
      ITERATIONS=10
      IPERF_SERVER=""
      IPERF_MSS=""
      IPERF_BW=""
      HOST_BENCH=""
      TARGET_NAME=""
      IRQBALANCE_HOST=""
      FLOOD=0
      SWEEP=0
      SWEEP_MIN=""
      SWEEP_MAX=""
      SWEEP_STEP="5M"
      NETEM=""
      NETEM_OFF=0
      RPS=""
      TRUNCATION=""

      TARGETS=(
        "8.8.8.8"
        "1.1.1.1"
        "9.9.9.9"
        "208.67.222.222"
      )

      usage() {
        cat <<'USAGE'
      Usage: ids-mirror-bench [OPTIONS]
        --iface         Physical NIC to monitor (auto-detected if not set)
        --window        Measurement window per ON/OFF slot in sec (default: 30)
        --iterations    Number of ON/OFF pairs (default: 10)
        --targets       Comma-separated IPs/hosts
        --iperf-server  iperf3 server host/IP (optional, runs at full speed)
        --bandwidth     iperf3 target bandwidth (e.g. 100M, 500M; default: unlimited)
        --mss           TCP MSS for iperf3 (default: OS default ~1460; use e.g. 512 to send small packets)
        --host-bench    Host IP for ids-bench-server CPU measurement (e.g. 192.168.100.1)
        --flood         Use flood ping instead of normal rate
        --sweep         Sweep bandwidth from MIN to MAX and plot CPU overhead vs BW
        --sweep-min     Lower bandwidth limit for sweep (default: same as step)
        --sweep-max     Upper bandwidth limit for sweep (e.g. 900M)
        --sweep-step    Bandwidth step size (default: 5M)
        --netem         Override netem params (e.g. "slot 30ms 50ms packets 1024 limit 4096")
        --no-netem      Remove the mirror tap's netem qdisc entirely (ids-mirror always adds one on start)
        --rps           off|MASK - set rps_cpus (hex mask, e.g. 3) + rps_flow_cnt on $IFACE's rx-0 before measuring; 'off' clears it
        --truncation    on|off - attach/detach the compiled eBPF snaplen filter on the mirror tap's egress
        --list-ifaces   List candidate physical NICs (name, IPv4, default-route, state, RPS, speed) and exit
      USAGE
        exit 0
      }

      # Physical NICs eligible for mirroring: excludes the "mirror" tap and
      # virtio_net VM interfaces. Shared by auto-detect, apply_rps, rps_status, --list-ifaces.
      mirror_candidate_ifaces() {
        local sysfs name driver
        for sysfs in /sys/class/net/*; do
          name=''${sysfs##*/}
          [ -e "$sysfs/device" ] || continue
          [[ "$name" == "mirror" ]] && continue
          driver=$(readlink "$sysfs/device/driver" 2>/dev/null || true)
          driver=''${driver##*/}
          [ "$driver" = "virtio_net" ] && continue
          echo "$name"
        done
      }

      list_ifaces() {
        local defdevs name ip4 dr rps sp
        defdevs=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | sort -u | tr '\n' ' ')
        for name in $(mirror_candidate_ifaces); do
          ip4=$(ip -4 -o addr show dev "$name" scope global 2>/dev/null | awk '{print $4; exit}')
          [ -z "$ip4" ] && ip4=no-address
          case " $defdevs " in *" $name "*) dr=default-route ;; *) dr=no-default-route ;; esac
          rps=$(cat "/sys/class/net/$name/queues/rx-0/rps_cpus" 2>/dev/null || echo "-")
          sp=$(cat "/sys/class/net/$name/speed" 2>/dev/null || echo "-")
          case "$sp" in "" | -1) sp="-" ;; esac
          echo "$name $ip4 $dr $(cat "/sys/class/net/$name/operstate" 2>/dev/null || echo unknown) rps=$rps speed=$sp"
        done
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
          --host-bench)
            if [[ $# -gt 1 && "''${2}" != --* ]]; then
              HOST_BENCH="''${2//[[:space:]]/}"; shift 2
            else
              HOST_BENCH=$(awk '/[[:space:]]ghaf-host([[:space:]]|$)/{print $1; exit}' /etc/hosts)
              shift 1
            fi
            ;;
          --flood)        FLOOD=1;           shift ;;
          --sweep)        SWEEP=1;           shift ;;
          --sweep-min)    SWEEP_MIN="$2";    shift 2 ;;
          --sweep-max)    SWEEP_MAX="$2";    shift 2 ;;
          --sweep-step)   SWEEP_STEP="$2";   shift 2 ;;
          --netem)        NETEM="$2";        shift 2 ;;
          --no-netem)     NETEM_OFF=1;       shift ;;
          --rps)          RPS="$2";          shift 2 ;;
          --truncation)   TRUNCATION="$2";   shift 2 ;;
          --targets)
            IFS=',' read -ra TARGETS <<< "$2"
            shift 2
            ;;
          --list-ifaces) list_ifaces ;;
          --help|-h) usage ;;
          *) err "unknown option: $1"; usage ;;
        esac
      done

      if [[ -z "$IFACE" ]]; then
        # Not `| head -1`: the producer's SIGPIPE would be fatal under pipefail.
        read -r IFACE < <(mirror_candidate_ifaces) || true
        [[ -n "$IFACE" ]] || { err "no physical NIC found; use --iface"; exit 1; }
      fi

      # --iface is user-supplied and unchecked; a stale name (e.g. a USB
      # re-plug bumping ueth6->ueth7) would otherwise fail later as a cryptic awk error.
      [ -e "/sys/class/net/$IFACE" ] || { err "interface '$IFACE' not found (check 'ip link show')"; exit 1; }

      # Targets every mirrored external interface (same discovery as the mirror
      # sender), not just $IFACE, so --rps can A/B test without a manual sysfs dance.
      apply_rps() {
        [[ -z "$RPS" ]] && return
        if [[ "$RPS" != "off" && ! "$RPS" =~ ^[0-9a-fA-F]+$ ]]; then
          err "--rps must be 'off' or a hex rps_cpus mask, got '$RPS'"
          exit 1
        fi
        [[ "$RPS" != "off" ]] && sysctl -w net.core.rps_sock_flow_entries=32768 >/dev/null 2>&1 || true
        local name
        for name in $(mirror_candidate_ifaces); do
          local f="/sys/class/net/$name/queues/rx-0/rps_cpus"
          local fc="/sys/class/net/$name/queues/rx-0/rps_flow_cnt"
          [ -e "$f" ] || continue
          if [[ "$RPS" != "off" ]]; then
            echo "$RPS" > "$f" 2>/dev/null || true
            [ -e "$fc" ] && { echo 32768 > "$fc" 2>/dev/null || true; }
            info "[rps] enabled on $name (mask=$RPS)"
          else
            echo 0 > "$f" 2>/dev/null || true
            [ -e "$fc" ] && { echo 0 > "$fc" 2>/dev/null || true; }
            info "[rps] disabled on $name"
          fi
        done
      }
      apply_rps

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

      # Static across pairs, so it's printed once in the header (netem_status) rather than every call.
      apply_netem() {
        if [[ "$NETEM_OFF" -eq 1 ]]; then
          # Strip netem back off to isolate its own overhead from the kernel's plain default.
          tc qdisc del dev mirror root 2>/dev/null || true
          return
        fi
        [[ -z "$NETEM" ]] && return
        tc qdisc del dev mirror root 2>/dev/null || true
        # shellcheck disable=SC2086
        tc qdisc add dev mirror root netem $NETEM
      }

      # Must be re-run after every `systemctl start ids-mirror`: mirrorStartScript
      # re-attaches its own build-time truncation state each restart, silently undoing --truncation off.
      apply_truncation() {
        [[ -z "$TRUNCATION" ]] && return
        local obj="/etc/ids-mirror/trunc.o"
        if [[ "$TRUNCATION" == "on" ]]; then
          if [ ! -e "$obj" ]; then
            err "$obj not found (system wasn't built with snaplen set); ignoring --truncation on"
            return
          fi
          tc qdisc del dev mirror clsact 2>/dev/null || true
          tc qdisc add dev mirror clsact 2>/dev/null || true
          tc filter del dev mirror egress 2>/dev/null || true
          tc filter add dev mirror egress bpf da obj "$obj" sec classifier \
            || { err "failed to attach truncation filter"; exit 1; }
        elif [[ "$TRUNCATION" == "off" ]]; then
          tc filter del dev mirror egress 2>/dev/null || true
          tc qdisc del dev mirror clsact 2>/dev/null || true
        else
          err "--truncation must be 'on' or 'off', got '$TRUNCATION'"
          exit 1
        fi
      }

      netem_status() {
        if [[ "$NETEM_OFF" -eq 1 ]]; then
          echo "disabled (--no-netem)"
        elif [[ -n "$NETEM" ]]; then
          echo "$NETEM"
        else
          echo "default (ids-mirror service default)"
        fi
      }

      # systemctl is-active prints the state to stdout regardless of exit
      # code, but the nonzero exit itself (any state but "active") still
      # kills the script under set -e once embedded in a string/array
      # assignment - `|| true` here, not just at the call site.
      irqbalance_local() {
        systemctl is-active irqbalance 2>/dev/null || true
      }

      # Off iff every mirrored interface's rx-0 mask is all-zero (same discovery as apply_rps).
      rps_status() {
        local parts=() name f val
        for name in $(mirror_candidate_ifaces); do
          f="/sys/class/net/$name/queues/rx-0/rps_cpus"
          [ -e "$f" ] || continue
          val=$(cat "$f" 2>/dev/null || echo "0")
          if [[ "''${val//[,0]/}" == "" ]]; then
            parts+=("$name=off")
          else
            parts+=("$name=on($val)")
          fi
        done
        [ "''${#parts[@]}" -eq 0 ] && { echo "n/a"; return; }
        echo "''${parts[*]}"
      }

      # If --truncation was given, report that intent directly: apply_truncation
      # only takes effect once pairs start, so a live tc query here would be stale.
      truncation_status() {
        if [[ -n "$TRUNCATION" ]]; then
          echo "$TRUNCATION"
        elif tc filter show dev mirror egress 2>/dev/null | grep -q "bpf"; then
          echo "on"
        else
          echo "off"
        fi
      }

      # Call after a window so counters reflect just it (qdisc is recreated each ON phase).
      print_netem_stats() {
        local stats
        # grep/[[ can each return 1 (empty match, or --no-netem removed the qdisc)
        # which set -euo pipefail would treat as fatal; `if` avoids propagating that.
        stats=$(tc -s qdisc show dev mirror 2>/dev/null | grep -A1 -m1 '^qdisc netem' || true)
        if [[ -n "$stats" ]]; then
          info "[netem stats] $stats"
        fi
      }

      measure_window() {
        local accdir="$1" slot="$TMPDIR/slot"
        mkdir -p "$slot"

        local cpu_idle_before cpu_total_before rx_before tx_before mem_before mirror_rx_before
        read -r cpu_idle_before cpu_total_before < <(awk '/^cpu /{idle=$5;s=0;for(i=2;i<=NF;i++)s+=$i;print idle,s;exit}' /proc/stat)
        rx_before=$(awk -v d="$IFACE:" '$1==d{print $2}' /proc/net/dev)
        tx_before=$(awk -v d="$IFACE:" '$1==d{print $10}' /proc/net/dev)
        mem_before=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{print t-a}' /proc/meminfo)
        mirror_rx_before=$(awk -v d="mirror:" '$1==d{print $10}' /proc/net/dev 2>/dev/null || true)
        mirror_rx_before="''${mirror_rx_before:-0}"

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

        if [[ -n "$HOST_BENCH" ]]; then
          (
            result=$(printf 'cpu %s\n' "$WINDOW" \
              | nc -w $((WINDOW + 5)) "$HOST_BENCH" 9999 2>/dev/null || true)
            if [[ -n "$result" ]]; then
              printf '%s\n' "$result" > "$slot/host_cpu"
            else
              warn "bench-server unreachable ($HOST_BENCH:9999)"
            fi
          ) &
          pids+=($!)
        fi

        for pid in "''${pids[@]}"; do wait "$pid" || true; done

        local cpu_idle_after cpu_total_after rx_after tx_after mem_after mirror_rx_after
        read -r cpu_idle_after cpu_total_after < <(awk '/^cpu /{idle=$5;s=0;for(i=2;i<=NF;i++)s+=$i;print idle,s;exit}' /proc/stat)
        rx_after=$(awk -v d="$IFACE:" '$1==d{print $2}' /proc/net/dev)
        tx_after=$(awk -v d="$IFACE:" '$1==d{print $10}' /proc/net/dev)
        mem_after=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{print t-a}' /proc/meminfo)
        mirror_rx_after=$(awk -v d="mirror:" '$1==d{print $10}' /proc/net/dev 2>/dev/null || true)
        mirror_rx_after="''${mirror_rx_after:-0}"

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

      stats() {
        [[ -f "$1" ]] || { echo "N/A"; return; }
        awk 'BEGIN{n=0;s=0;s2=0}
             /^[0-9]/{n++;s+=$1;s2+=$1*$1}
             END{
               if(n==0){print "N/A"; exit}
               mean=s/n
               # variance can go slightly negative from float cancellation
               # on near-identical values; clamp before sqrt to avoid -nan.
               variance=(n>1)?(s2-s*s/n)/(n-1):0
               if (variance < 0) variance = 0
               std=sqrt(variance)
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

      bw_to_mbps() {
        awk -v v="$1" 'BEGIN{
          n=v+0; u=substr(v,length(v))
          if(u=="G"||u=="g") printf "%.2f", n*1000
          else if(u=="K"||u=="k") printf "%.2f", n/1000
          else printf "%.2f", n
        }'
      }

      mirror_on() {
        systemctl start ids-mirror 2>/dev/null || true
        apply_netem
        apply_truncation
      }

      mirror_off() {
        systemctl stop ids-mirror 2>/dev/null || true
      }

      query_host_bench() {
        TARGET_NAME=$(printf 'hostname\n' | nc -w 3 "$HOST_BENCH" 9999 2>/dev/null || true)
        IRQBALANCE_HOST=$(printf 'irqbalance\n' | nc -w 3 "$HOST_BENCH" 9999 2>/dev/null || true)
      }

      check_iperf3_server() {
        local server="$1" _try
        info "checking iperf3 server $server..."
        for _try in 1 2 3; do
          if iperf3 -c "$server" -t 1 -b 1M >/dev/null 2>&1; then
            info "iperf3 server $server reachable"
            return
          fi
          if [[ "$_try" -eq 3 ]]; then
            err "cannot reach iperf3 server $server — details:"
            iperf3 -c "$server" -t 1 -b 1M >&2 || true
            exit 1
          fi
          warn "iperf3 server $server unreachable, retry $_try/3"
          sleep 2
        done
      }

      if [[ "$SWEEP" -eq 1 ]]; then
        # preflight
        [[ -n "$IPERF_SERVER" ]] || { err "--sweep requires --iperf-server"; exit 1; }
        [[ -n "$SWEEP_MAX"   ]] || { err "--sweep requires --sweep-max";    exit 1; }

        check_iperf3_server "$IPERF_SERVER"
        echo ""

        # parse the sweep range
        max_mbps=$(bw_to_mbps "$SWEEP_MAX")
        step_mbps=$(bw_to_mbps "$SWEEP_STEP")
        min_mbps=$(bw_to_mbps "''${SWEEP_MIN:-$SWEEP_STEP}")
        SWEEP_DAT="$TMPDIR/sweep.dat"

        # host bench info for the header, if configured
        if [[ -n "$HOST_BENCH" ]]; then
          query_host_bench
          # The server serves one connection then restarts ~1s later; wait
          # it out so the first host_cpu query doesn't race the restart.
          sleep 1
        fi

        # header
        rows=(
          "iperf3 server|$IPERF_SERVER"
          "Iterations|$ITERATIONS × ''${WINDOW}s per step"
          "irqbalance|net-vm=$(irqbalance_local)''${IRQBALANCE_HOST:+  host=$IRQBALANCE_HOST}"
          "truncation|$(truncation_status)"
          "netem|$(netem_status)"
          "rps|$(rps_status)"
        )
        [[ -n "$TARGET_NAME" ]] && rows=("Target|$TARGET_NAME" "''${rows[@]}")
        report "IDS Mirror BW Sweep  (''${SWEEP_MIN:-$SWEEP_STEP} → $SWEEP_MAX, step $SWEEP_STEP)" "''${rows[@]}"
        echo ""

        # Warmup — discarded; stabilises page cache, iperf connections, CPU state
        info "warmup..."
        IPERF_BW="''${SWEEP_MIN:-$SWEEP_STEP}"
        wD="$TMPDIR/warmup"; mkdir -p "$wD"
        mirror_on; sleep 1
        measure_window "$wD"
        mirror_off; sleep 1
        measure_window "$wD"
        rm -rf "$wD"
        echo ""

        # walk the bandwidth range, one step at a time
        bw_mbps="$min_mbps"
        while awk "BEGIN{exit !($bw_mbps <= $max_mbps)}"; do
          bw_label="''${bw_mbps%.*}M"
          IPERF_BW="$bw_label"
          sON="$TMPDIR/sw_on"; sOFF="$TMPDIR/sw_off"
          mkdir -p "$sON" "$sOFF"

          printf "  %-8s  measuring...\n" "$bw_label"
          # interleaved ON/OFF pairs at this bandwidth
          for i in $(seq 1 "$ITERATIONS"); do
            mirror_on; sleep 1
            measure_window "$sON"
            print_netem_stats
            mirror_off; sleep 1
            measure_window "$sOFF"
          done
          mirror_on

          cpu_d=$(delta "$sOFF/cpu" "$sON/cpu")
          host_cpu_d=$(delta "$sOFF/host_cpu" "$sON/host_cpu")
          ram_d=$(delta "$sOFF/mem" "$sON/mem")
          iperf_on=$(mean_val "$sON/iperf_bw")
          iperf_off=$(mean_val "$sOFF/iperf_bw")
          printf "            cpu_delta=%-8s  host_cpu_delta=%-8s  ram_delta=%-8s  iperf_ON=%-8s  iperf_OFF=%s Mbps\n" \
            "$cpu_d" "$host_cpu_d" "$ram_d" "$iperf_on" "$iperf_off"
          # record this step's result for the plots below
          awk -v bw="$bw_mbps" -v cpu="$cpu_d" -v hcpu="$host_cpu_d" -v ram="$ram_d" \
              -v ion="$iperf_on" -v ioff="$iperf_off" \
            'BEGIN{
              c=cpu+0; h=hcpu+0; r=ram+0; on=ion+0; off=ioff+0
              penalty=(off>0) ? (off-on)/off*100 : 0
              printf "%s %.2f %.2f %.2f %.2f %.2f %.2f\n", bw, \
                (c<0)?0:c, (r<0)?0:r, on, off, (penalty<0)?0:penalty, (h<0)?0:h
            }' >> "$SWEEP_DAT"
          rm -rf "$sON" "$sOFF"

          bw_mbps=$(awk "BEGIN{printf \"%.2f\", $bw_mbps + $step_mbps}")
        done

        # renders one SWEEP_DAT column as a dumb-terminal bar chart
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

        # CPU/RAM overhead plots
        _gplot_single "CPU Overhead vs Bandwidth (net-vm)"  "CPU delta (%)"   2 "#FF4444"
        [[ -n "$HOST_BENCH" ]] && \
          _gplot_single "CPU Overhead vs Bandwidth (host)"  "CPU delta (%)"   7 "#FF8800"
        _gplot_single "RAM Overhead vs Bandwidth"   "RAM delta (MiB)" 3 "#4488FF"

        # throughput penalty plot
        max_penalty=$(awk 'BEGIN{m=0} /^[0-9]/{if($6+0>m)m=$6+0} END{printf "%.4f",m}' "$SWEEP_DAT")
        if awk "BEGIN{exit !($max_penalty < 0.05)}"; then
          echo ""
          echo "  iperf3 Throughput Penalty vs Bandwidth"
          echo "  --------------------------------------"
          echo "  (max penalty ''${max_penalty}% — below 0.05% threshold, no measurable throughput impact)"
        else
          _gplot_single "iperf3 Throughput Penalty vs Bandwidth" "BW penalty %" 6 "#44BB44"
        fi

        echo ""
        exit 0
      fi

      [[ -n "$IPERF_SERVER" ]] && check_iperf3_server "$IPERF_SERVER"

      if [[ "$FLOOD" -eq 1 ]]; then
        MODE_DESC="flood (1400-byte, max rate)"
      else
        MODE_DESC="normal (64-byte, 5 pkt/s)"
      fi

      TOTAL=$(( ITERATIONS * 2 * WINDOW ))
      if [[ -n "$HOST_BENCH" ]]; then
        query_host_bench
        # The server serves one connection then restarts ~1s later; wait it
        # out so the first pair's host_cpu query doesn't race the restart.
        sleep 1
      fi

      rows=("Interface|$IFACE")
      [[ -n "$TARGET_NAME" ]] && rows+=("Target|$TARGET_NAME")
      rows+=(
        "Mode|$MODE_DESC"
        "Window|''${WINDOW}s × ''${ITERATIONS} pairs = ''${TOTAL}s total"
      )
      [[ -n "$IPERF_SERVER" ]] && rows+=("iperf3|$IPERF_SERVER  MSS=''${IPERF_MSS:-default}  BW=''${IPERF_BW:-unlimited}")
      [[ -n "$HOST_BENCH" ]] && rows+=("host bench|$HOST_BENCH")
      rows+=(
        "irqbalance|net-vm=$(irqbalance_local)''${IRQBALANCE_HOST:+  host=$IRQBALANCE_HOST}"
        "truncation|$(truncation_status)"
        "netem|$(netem_status)"
        "rps|$(rps_status)"
      )
      report "IDS Mirror Overhead Benchmark" "''${rows[@]}"
      echo ""

      ON_DIR="$TMPDIR/on"
      OFF_DIR="$TMPDIR/off"
      mkdir -p "$ON_DIR" "$OFF_DIR"

      for i in $(seq 1 "$ITERATIONS"); do
        echo "  Pair $i/$ITERATIONS — Mirror ON..."
        mirror_on; sleep 1
        measure_window "$ON_DIR"
        print_netem_stats

        echo "  Pair $i/$ITERATIONS — Mirror OFF..."
        mirror_off; sleep 1
        measure_window "$OFF_DIR"
      done

      mirror_on

      row() {
        printf "  %-28s  %-20s  %-20s  %s\n" "$@"
      }

      echo ""
      echo "========================================================"
      echo "  Results (mean ± stddev over $ITERATIONS pairs)"
      echo "========================================================"
      row "Metric" "Mirror ON" "Mirror OFF" "Delta"
      row "------" "---------" "----------" "-----"
      row \
        "CPU usage / net-vm (%):" \
        "$(stats "$ON_DIR/cpu")" \
        "$(stats "$OFF_DIR/cpu")" \
        "$(delta "$OFF_DIR/cpu" "$ON_DIR/cpu")%"
      if [[ -n "$HOST_BENCH" ]]; then
        row \
          "CPU usage / host (%):" \
          "$(stats "$ON_DIR/host_cpu")" \
          "$(stats "$OFF_DIR/host_cpu")" \
          "$(delta "$OFF_DIR/host_cpu" "$ON_DIR/host_cpu")%"
      fi
      row \
        "TX throughput (Mbps):" \
        "$(stats "$ON_DIR/tx")" \
        "$(stats "$OFF_DIR/tx")" \
        "$(delta "$OFF_DIR/tx" "$ON_DIR/tx") Mbps"
      if [[ "$FLOOD" -eq 0 ]]; then
        row \
          "Latency avg (ms):" \
          "$(stats "$ON_DIR/lat")" \
          "$(stats "$OFF_DIR/lat")" \
          "$(delta "$OFF_DIR/lat" "$ON_DIR/lat") ms"
        row \
          "Packet loss (%):" \
          "$(stats "$ON_DIR/loss")" \
          "$(stats "$OFF_DIR/loss")"
      fi
      row \
        "RAM used (MiB):" \
        "$(stats "$ON_DIR/mem")" \
        "$(stats "$OFF_DIR/mem")" \
        "$(delta "$OFF_DIR/mem" "$ON_DIR/mem") MiB"
      if [[ -n "$IPERF_SERVER" ]]; then
        row \
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
  };

  server = pkgs.writeShellApplication {
    name = "ids-bench-server";
    runtimeInputs = [
      pkgs.netcat-openbsd
      pkgs.gawk
    ];
    text = ''
      info() {
        printf 'ids-bench-server: [info] %s\n' "$*"
      }

      warn() {
        printf 'ids-bench-server: [warn] %s\n' "$*" >&2
      }

      PORT=''${1:-9999}

      measure_cpu() {
        local window="$1" idle_b total_b idle_a total_a
        read -r idle_b total_b < <(
          awk '/^cpu /{s=0;for(i=2;i<=NF;i++)s+=$i;print $5,s;exit}' /proc/stat
        )
        sleep "$window"
        read -r idle_a total_a < <(
          awk '/^cpu /{s=0;for(i=2;i<=NF;i++)s+=$i;print $5,s;exit}' /proc/stat
        )
        awk -v bi="$idle_b" -v bt="$total_b" -v ai="$idle_a" -v at="$total_a" \
          'BEGIN{d=at-bt;printf "%.2f\n",(d>0)?(1-(ai-bi)/d)*100:0}'
      }

      info "listening on :$PORT"
      while true; do
        coproc NC { nc -l "$PORT" 2>/dev/null; }
        nc_rfd=''${NC[0]}
        nc_wfd=''${NC[1]}
        cmd="" arg=""
        if read -r cmd arg <&"$nc_rfd" 2>/dev/null; then
          case "$cmd" in
            cpu)
              result=$(measure_cpu "''${arg:-10}")
              printf '%s\n' "$result" >&"$nc_wfd" || true
              ;;
            hostname)
              # DMI (x86) first, then device-tree model (ARM/Jetson), then hostname as a last resort.
              product=$(cat /sys/class/dmi/id/product_sku 2>/dev/null || true)
              [[ -z "$product" || "$product" == "Unknown" ]] && \
                product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
              [[ -z "$product" || "$product" == "Unknown" ]] && \
                product=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || true)
              [[ -z "$product" ]] && product=$(hostname)
              printf '%s\n' "$product" >&"$nc_wfd" || true
              ;;
            irqbalance)
              status=$(systemctl is-active irqbalance 2>/dev/null || true)
              printf '%s\n' "$status" >&"$nc_wfd" || true
              ;;
            *)
              [[ -n "$cmd" ]] && warn "unknown: $cmd"
              ;;
          esac
        fi
        exec {nc_rfd}<&- || true
        exec {nc_wfd}>&- || true
        wait "''${NC_PID:-}" 2>/dev/null || true
      done
    '';
  };
in
pkgs.symlinkJoin {
  name = "ids-mirror-bench";
  paths = [
    bench
    server
  ];
  meta.mainProgram = "ids-mirror-bench";
}
