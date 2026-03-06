#!/bin/sh /etc/rc.common
# ==============================================================================
# Telemt MTProxy Service Management Script
# Version: 3.2.1-1 (API v1, Hot-Reload, Adaptive ME Pool)
# ==============================================================================
START=99
STOP=10
USE_PROCD=1
CONF=/var/etc/telemt.toml

extra_command "run_save_stats" "Force dump prometheus metrics to RAM before shutdown"

PROG="$(command -v telemt 2>/dev/null || echo /usr/bin/telemt)"

is_cidr() { case "$1" in *[!0-9A-Fa-f:./]* ) return 1 ;; esac; echo "$1" | grep -qE '^[0-9A-Fa-f:.]+/[0-9]{1,3}$'; }
is_uint() { echo "$1" | grep -qE '^[0-9]+$'; }
sanitize_toml_value() { printf '%s' "$1" | tr -d '\n\r' | sed 's/["\\]/\\&/g'; }

fetch_metrics() {
    local url="$1"
    if command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -q --timeout=3 -O - "$url"
    elif command -v wget >/dev/null 2>&1; then wget -q --timeout=3 -O - "$url"
    else return 1; fi
}

run_save_stats() {
    local m_port=$(uci -q get telemt.general.metrics_port || echo 9092)
    local tmp_file="/tmp/telemt_stats.txt"
    local tmp_live=$(mktemp /tmp/telemt_live.XXXXXX)
    local tmp_stat=$(mktemp /tmp/telemt_stats.XXXXXX)
    trap 'rm -f "$tmp_live" "$tmp_stat"' EXIT INT TERM
    
    local pid=$(pidof telemt 2>/dev/null | awk '{print $1}')
    if [ -z "$pid" ]; then return 0; fi
    
    local raw=$(fetch_metrics "http://127.0.0.1:${m_port}/metrics" 2>/dev/null)
    if [ -z "$raw" ]; then return 0; fi
    touch "$tmp_file" 2>/dev/null
    
    echo "$raw" | awk '
    /^telemt_user_octets_to_client/ { match($0, /user="[^"]+"/); if(RSTART) { u=substr($0, RSTART+6, RLENGTH-7); tx[u]+=$2; users[u]=1 } }
    /^telemt_user_octets_from_client/ { match($0, /user="[^"]+"/); if(RSTART) { u=substr($0, RSTART+6, RLENGTH-7); rx[u]+=$2; users[u]=1 } }
    END { for(u in users) printf "%s %.0f %.0f\n", u, tx[u], rx[u] }
    ' > "$tmp_live"

    if [ -s "$tmp_live" ]; then
        cat "$tmp_live" "$tmp_file" 2>/dev/null | awk '
        NF==3 { tx[$1] += $2; rx[$1] += $3; users[$1]=1 }
        END { for(u in users) printf "%s %.0f %.0f\n", u, tx[u], rx[u] }
        ' > "$tmp_stat"
        if [ -s "$tmp_stat" ]; then mv "$tmp_stat" "$tmp_file"; fi
    fi
}

generate_toml() {
    local target_file="$1"
    
    local enabled mode port api_port metrics_port m_alo m_alan metrics_whitelist domain log_level use_mp use_stun ad_tag announce_ip external_ip
    local tm_handshake tm_connect tm_keepalive tm_ack listen_ipv4 listen_ipv6 prefer_ip fake_cert_len tls_full_cert_ttl_secs replay_window_secs ignore_time_skew
    local me_pool_size me_warm_standby hardswap me_drain_ttl auto_deg deg_min_dc desync_all mask_proxy_protocol minimal_rt
    
    # Adaptive ME parameters
    local me_floor_mode me_idle_secs me_grace_secs me_min_single me_shadow_writers me_outage_mode me_outage_no_quarantine me_shadow_rotate
    
    local TMP_LINKS=$(mktemp /tmp/telemt_links.XXXXXX)
    local TMP_USERS=$(mktemp /tmp/telemt_users.XXXXXX)
    local TMP_CONNS=$(mktemp /tmp/telemt_conns.XXXXXX)
    local TMP_IPS=$(mktemp /tmp/telemt_ips.XXXXXX)
    local TMP_QUOTA=$(mktemp /tmp/telemt_quota.XXXXXX)
    local TMP_EXP=$(mktemp /tmp/telemt_exp.XXXXXX)
    local TMP_CONF=$(mktemp /var/etc/telemt.toml.XXXXXX)
    
    trap 'rm -f "$TMP_LINKS" "$TMP_USERS" "$TMP_CONNS" "$TMP_IPS" "$TMP_QUOTA" "$TMP_EXP" "$TMP_CONF"' EXIT INT TERM
    
    config_get mode general mode "tls"
    config_get port general port "4443"
    config_get metrics_port general metrics_port "9092"
    config_get api_port general api_port "9091"
    
    # Auto-resolve port conflict for upgrading users
    if [ "$metrics_port" -eq "$api_port" ]; then
        api_port=$((metrics_port + 1))
        logger -t telemt "Init: Port conflict detected. Auto-shifted Control API to $api_port"
    fi
    
    config_get_bool m_alo general metrics_allow_lo 1
    config_get_bool m_alan general metrics_allow_lan 1
    config_get metrics_whitelist general metrics_whitelist ""
    config_get log_level general log_level "normal"
    config_get domain general domain "google.com"
    config_get external_ip general external_ip ""
    config_get_bool listen_ipv4 general listen_ipv4 1
    config_get_bool listen_ipv6 general listen_ipv6 0
    config_get prefer_ip general prefer_ip "4"
    config_get tm_handshake general tm_handshake "15"
    config_get tm_connect general tm_connect "10"
    config_get tm_keepalive general tm_keepalive "60"
    config_get tm_ack general tm_ack "300"
    
    config_get_bool use_mp general use_middle_proxy 0
    config_get_bool use_stun general use_stun 1
    config_get me_pool_size general me_pool_size "16"
    config_get me_warm_standby general me_warm_standby "8"
    config_get_bool hardswap general hardswap 1
    config_get me_drain_ttl general me_drain_ttl "90"
    config_get_bool auto_deg general auto_degradation 1
    config_get deg_min_dc general degradation_min_dc "2"
    
    config_get me_floor_mode general me_floor_mode "static"
    config_get me_idle_secs general me_adaptive_floor_idle_secs "600"
    config_get me_grace_secs general me_adaptive_floor_recover_grace_secs "120"
    config_get me_min_single general me_adaptive_floor_min_writers_single_endpoint "1"
    config_get me_shadow_writers general me_single_endpoint_shadow_writers "2"
    config_get_bool me_outage_mode general me_single_endpoint_outage_mode_enabled 1
    config_get_bool me_outage_no_quarantine general me_single_endpoint_outage_disable_quarantine 1
    config_get me_shadow_rotate general me_single_endpoint_shadow_rotate_every_secs "900"
    
    config_get_bool desync_all general desync_all_full 0
    config_get ad_tag general ad_tag ""
    config_get announce_ip general announce_ip ""
    config_get fake_cert_len general fake_cert_len "2048"
    config_get tls_full_cert_ttl_secs general tls_full_cert_ttl_secs "90"
    config_get replay_window_secs general replay_window_secs "1800"
    config_get_bool ignore_time_skew general ignore_time_skew 0
    config_get mask_proxy_protocol general mask_proxy_protocol "0"
    config_get_bool minimal_rt general minimal_runtime_enabled 1
    
    domain=$(echo "$domain" | tr -cd 'A-Za-z0-9.-')
    ad_tag=$(sanitize_toml_value "$ad_tag" | tr -cd 'A-Fa-f0-9')
    announce_ip=$(sanitize_toml_value "$announce_ip")
    if [ -n "$external_ip" ]; then external_ip=$(echo "$external_ip" | awk '{print $1}'); fi
    if [ -z "$announce_ip" ] && [ -n "$external_ip" ]; then announce_ip="$external_ip"; fi
    
    local mp_str="false"; [ "$use_mp" -eq 1 ] && mp_str="true"
    local stun_str="false"; [ "$use_stun" -eq 1 ] && stun_str="true"
    local v4_str="false"; [ "$listen_ipv4" -eq 1 ] && v4_str="true"
    local v6_str="false"; [ "$listen_ipv6" -eq 1 ] && v6_str="true"
    local time_skew_str="false"; [ "$ignore_time_skew" -eq 1 ] && time_skew_str="true"
    local hardswap_str="false"; [ "$hardswap" -eq 1 ] && hardswap_str="true"
    local auto_deg_str="false"; [ "$auto_deg" -eq 1 ] && auto_deg_str="true"
    local minimal_rt_str="false"; [ "$minimal_rt" -eq 1 ] && minimal_rt_str="true"
    local m_cls="false"; local m_sec="false"; local m_tls="false"
    
    case "$mode" in "classic") m_cls="true" ;; "dd") m_sec="true" ;; "all") m_cls="true"; m_sec="true"; m_tls="true" ;; *) m_tls="true" ;; esac

    local wl_toml=""
    [ "$m_alo" -eq 1 ] && wl_toml="\"127.0.0.1/32\", \"::1/128\""
    
    if [ "$m_alan" -eq 1 ]; then
        local lan_ip=$(uci -q get network.lan.ipaddr)
        if [ -z "$lan_ip" ]; then
            lan_ip=$(ubus call network.interface.lan status 2>/dev/null | grep -A2 'ipv4-address' | grep address | awk -F'"' '{print $4}')
            local lan_mask=$(ubus call network.interface.lan status 2>/dev/null | grep -A2 'ipv4-address' | grep mask | awk '{print $2}' | tr -d ',')
        else
            local lan_mask=$(uci -q get network.lan.netmask)
        fi
        
        if [ -n "$lan_ip" ] && [ -n "$lan_mask" ] && [ -x /bin/ipcalc.sh ]; then
            eval $(/bin/ipcalc.sh "$lan_ip" "$lan_mask" 2>/dev/null)
            if [ -n "$NETWORK" ] && [ -n "$PREFIX" ]; then
                if ! echo "$wl_toml" | grep -q "\"$NETWORK/$PREFIX\""; then
                    [ -n "$wl_toml" ] && wl_toml="${wl_toml}, "
                    wl_toml="${wl_toml}\"$NETWORK/$PREFIX\""
                fi
            fi
        fi
    fi

    for raw in $(echo "$metrics_whitelist" | tr ',' ' '); do
        ip="$(echo "$raw" | tr -d ' \t\r\n')"; [ -z "$ip" ] && continue
        if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then ip="$ip/32"
        elif echo "$ip" | grep -qE '^[0-9A-Fa-f:]+$'; then ip="$ip/128"; fi
        if is_cidr "$ip"; then 
            if ! echo "$wl_toml" | grep -q "\"$ip\""; then [ -n "$wl_toml" ] && wl_toml="${wl_toml}, "; wl_toml="${wl_toml}\"$ip\""; fi
        fi
    done

    # ================= CORE CONFIGURATION (REQUIRES RESTART ON CHANGE) =================
    cat <<TOML > "$TMP_CONF"
[network]
ipv4 = $v4_str
ipv6 = $v6_str
prefer = $prefer_ip
stun_servers = [
  "stun.l.google.com:5349",
  "stun1.l.google.com:3478",
  "stun.l.google.com:19302",
  "stun1.l.google.com:19302"
]
stun_tcp_fallback = true

[general]
fast_mode = true
use_middle_proxy = $mp_str
log_level = "$log_level"
TOML

    if [ "$use_mp" -eq 1 ]; then
        cat <<TOML >> "$TMP_CONF"
middle_proxy_nat_probe = $stun_str
middle_proxy_pool_size = $me_pool_size
middle_proxy_warm_standby = $me_warm_standby
hardswap = $hardswap_str
me_pool_drain_ttl_secs = $me_drain_ttl
auto_degradation_enabled = $auto_deg_str
degradation_min_unavailable_dc_groups = $deg_min_dc

floor_mode = "$me_floor_mode"
adaptive_floor_idle_secs = $me_idle_secs
adaptive_floor_recover_grace_secs = $me_grace_secs
adaptive_floor_min_writers_single_endpoint = $me_min_single

me_single_endpoint_shadow_writers = $me_shadow_writers
me_single_endpoint_outage_mode_enabled = $( [ "$me_outage_mode" -eq 1 ] && echo "true" || echo "false" )
me_single_endpoint_outage_disable_quarantine = $( [ "$me_outage_no_quarantine" -eq 1 ] && echo "true" || echo "false" )
me_single_endpoint_shadow_rotate_every_secs = $me_shadow_rotate
TOML
    fi

    if [ "$desync_all" -eq 1 ]; then echo "desync_all_full = true" >> "$TMP_CONF"; fi
    [ -n "$ad_tag" ] && echo "ad_tag = \"$ad_tag\"" >> "$TMP_CONF"

    mkdir -p /var/etc/telemt_tlsfront

    cat <<TOML >> "$TMP_CONF"

[general.modes]
classic = $m_cls
secure = $m_sec
tls = $m_tls

[server]
port = $port
metrics_port = $metrics_port
metrics_whitelist = [$wl_toml]
TOML

    if [ "$listen_ipv4" -eq 1 ]; then echo "listen_addr_ipv4 = \"0.0.0.0\"" >> "$TMP_CONF"; fi
    if [ "$listen_ipv6" -eq 1 ]; then echo "listen_addr_ipv6 = \"::\"" >> "$TMP_CONF"; fi

    cat <<TOML >> "$TMP_CONF"

[server.api]
enabled = true
listen = "127.0.0.1:${api_port}"
whitelist = ["127.0.0.1/32", "::1/128"]
minimal_runtime_enabled = $minimal_rt_str
minimal_runtime_cache_ttl_ms = 1000

[timeouts]
client_handshake = $tm_handshake
tg_connect = $tm_connect
client_keepalive = $tm_keepalive
client_ack = $tm_ack

[censorship]
tls_domain = "$domain"
mask = true
mask_port = 443
mask_proxy_protocol = $mask_proxy_protocol
tls_emulation = true
tls_front_dir = "/var/etc/telemt_tlsfront"
fake_cert_len = $fake_cert_len
tls_full_cert_ttl_secs = $tls_full_cert_ttl_secs

[access]
replay_check_len = 65536
replay_window_secs = $replay_window_secs
ignore_time_skew = $time_skew_str

# --- DYNAMIC CONFIG ---
TOML
    # ================= DYNAMIC CONFIGURATION (HOT-RELOADABLE) =================

    is_user_enabled() { local en; config_get_bool en "$1" enabled 1; [ "$en" -eq 1 ]; }
    add_user_link() { is_user_enabled "$1" || return 0; printf '"%s", ' "$1" >> "$TMP_LINKS"; }
    add_user_secret() { is_user_enabled "$1" || return 0; local sec; config_get sec "$1" secret; if [ -n "$sec" ]; then echo "$1 = \"$sec\"" >> "$TMP_USERS"; fi; }
    add_user_conns() { is_user_enabled "$1" || return 0; local c; config_get c "$1" max_tcp_conns; if [ -n "$c" ] && [ "$c" != "unlimited" ] && is_uint "$c"; then echo "$1 = $c" >> "$TMP_CONNS"; fi; }
    add_user_unique_ips() { is_user_enabled "$1" || return 0; local i; config_get i "$1" max_unique_ips; if [ -n "$i" ] && [ "$i" != "unlimited" ] && is_uint "$i"; then echo "$1 = $i" >> "$TMP_IPS"; fi; }
    add_user_quota() { is_user_enabled "$1" || return 0; local q; config_get q "$1" data_quota; if [ -n "$q" ] && [ "$q" != "unlimited" ]; then local b=$(echo "$q" | sed 's/,/\./g' | awk '{printf "%.0f", $1 * 1073741824}'); if [ -n "$b" ] && is_uint "$b"; then echo "$1 = $b" >> "$TMP_QUOTA"; fi; fi; }
    add_user_expiration() { is_user_enabled "$1" || return 0; local exp; config_get exp "$1" expire_date; if [ -n "$exp" ] && [ "$exp" != "unlimited" ]; then local fmt=$(echo "$exp" | awk -F'[. :]' 'NF==5 {printf "%04d-%02d-%02dT%02d:%02d:00Z", $3, $2, $1, $4, $5}'); if [ -n "$fmt" ]; then echo "$1 = \"$fmt\"" >> "$TMP_EXP"; fi; fi; }

    config_foreach add_user_link user
    local links_str=""; [ -s "$TMP_LINKS" ] && links_str=$(sed 's/, $//' "$TMP_LINKS")
    printf '\n[general.links]\nshow = [%s]\n' "$links_str" >> "$TMP_CONF"
    
    if [ -n "$announce_ip" ]; then printf 'public_host = "%s"\n' "$announce_ip" >> "$TMP_CONF"; fi

    printf '\n[access.users]\n' >> "$TMP_CONF"
    config_foreach add_user_secret user
    [ -s "$TMP_USERS" ] && cat "$TMP_USERS" >> "$TMP_CONF"
    
    config_foreach add_user_conns user
    if [ -s "$TMP_CONNS" ]; then printf '\n[access.user_max_tcp_conns]\n' >> "$TMP_CONF"; cat "$TMP_CONNS" >> "$TMP_CONF"; fi
    
    config_foreach add_user_unique_ips user
    if [ -s "$TMP_IPS" ]; then printf '\n[access.user_max_unique_ips]\n' >> "$TMP_CONF"; cat "$TMP_IPS" >> "$TMP_CONF"; fi
    
    config_foreach add_user_quota user
    if [ -s "$TMP_QUOTA" ]; then printf '\n[access.user_data_quota]\n' >> "$TMP_CONF"; cat "$TMP_QUOTA" >> "$TMP_CONF"; fi
    
    config_foreach add_user_expiration user
    if [ -s "$TMP_EXP" ]; then printf '\n[access.user_expirations]\n' >> "$TMP_CONF"; cat "$TMP_EXP" >> "$TMP_CONF"; fi
    
    local has_upstreams=0
    handle_upstream() {
        local s="$1"
        local u_en u_type u_addr u_user u_pass u_weight
        config_get_bool u_en "$s" enabled 0
        [ "$u_en" -ne 1 ] && return
        
        config_get u_type "$s" type "direct"
        config_get u_weight "$s" weight "10"
        
        # SAFETY FIX: Ignore SOCKS upstreams with empty addresses to prevent backend crash
        if [ "$u_type" != "direct" ]; then
            config_get u_addr "$s" address ""
            if [ -z "$u_addr" ]; then return; fi
        fi

        printf '\n[[upstreams]]\n' >> "$TMP_CONF"
        echo "type = \"$u_type\"" >> "$TMP_CONF"
        echo "weight = $u_weight" >> "$TMP_CONF"
        echo "enabled = true" >> "$TMP_CONF"
        
        if [ "$u_type" != "direct" ]; then
            config_get u_user "$s" username ""
            config_get u_pass "$s" password ""
            echo "address = \"$(sanitize_toml_value "$u_addr")\"" >> "$TMP_CONF"
            [ -n "$u_user" ] && echo "username = \"$(sanitize_toml_value "$u_user")\"" >> "$TMP_CONF"
            [ -n "$u_pass" ] && echo "password = \"$(sanitize_toml_value "$u_pass")\"" >> "$TMP_CONF"
        fi
        has_upstreams=1
    }
    config_foreach handle_upstream upstream

    if [ "$has_upstreams" -eq 0 ]; then
        printf '\n[[upstreams]]\ntype = "direct"\nenabled = true\nweight = 10\n' >> "$TMP_CONF"
    fi
    
    mv "$TMP_CONF" "$target_file"
    rm -f "$TMP_USERS" "$TMP_CONNS" "$TMP_QUOTA" "$TMP_IPS" "$TMP_LINKS" "$TMP_EXP" "$TMP_CONF"
    trap - EXIT INT TERM
}

start_service() {
    umask 077
    config_load telemt
    
    local enabled
    config_get_bool enabled general enabled 0
    if [ "$enabled" -ne 1 ]; then return 0; fi

    if [ -x "$PROG" ]; then
        mkdir -p /var/etc
        local ver=$(grep -a -m1 -i 'MTProxy v' "$PROG" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        if [ -n "$ver" ]; then echo "$ver" > /var/etc/telemt.version; chmod 644 /var/etc/telemt.version; fi
    fi

    generate_toml "$CONF"
    chmod 600 "$CONF"
    
    local port auto_fw
    config_get port general port "4443"
    config_get_bool auto_fw general auto_fw 0
    
    procd_open_instance
    procd_set_param command "$PROG" "$CONF"
    procd_set_param file "$CONF"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 3600 30 0
    procd_set_param limits nofile="65536 65536"
    
    if [ "$auto_fw" -eq 1 ]; then
        procd_open_data
        json_add_array firewall
        json_add_object ""
            json_add_string type rule
            json_add_string name "Allow-Telemt-Magic"
            json_add_string src "wan"
            json_add_string dest_port "$port"
            json_add_string proto "tcp"
            json_add_string target "ACCEPT"
        json_close_object
        json_close_array
        procd_close_data
    fi
    procd_close_instance
}

reload_service() {
    umask 077
    config_load telemt
    
    local enabled
    config_get_bool enabled general enabled 0
    if [ "$enabled" -ne 1 ]; then 
        stop_service
        return 0
    fi
    
    local NEW_CONF="/tmp/telemt.toml.new"
    generate_toml "$NEW_CONF"
    chmod 600 "$NEW_CONF"
    
    # Safe Diff: Check if core settings changed (above the DYNAMIC CONFIG marker)
    sed -n '1,/^# --- DYNAMIC CONFIG ---/p' "$CONF" 2>/dev/null > /tmp/telemt_core.old
    sed -n '1,/^# --- DYNAMIC CONFIG ---/p' "$NEW_CONF" > /tmp/telemt_core.new
    
    if cmp -s /tmp/telemt_core.old /tmp/telemt_core.new; then
        # Core did not change. Replace file silently for hot-reload
        mv "$NEW_CONF" "$CONF"
        logger -t telemt "WebUI: Users/Upstreams updated. Executed Hot-Reload (no connections dropped)."
    else
        # Core settings changed. Full daemon restart is required
        mv "$NEW_CONF" "$CONF"
        logger -t telemt "WebUI: Core settings changed. Performing hard restart of telemt."
        restart
    fi
    
    rm -f /tmp/telemt_core.old /tmp/telemt_core.new
}

stop_service() {
    [ "$TELEMT_NO_SAVE" != "1" ] && run_save_stats
    killall -9 telemt 2>/dev/null
}

service_triggers() { 
    procd_add_reload_trigger "telemt"; 
}
