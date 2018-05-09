#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

section "A p a c h e   D r i l l"

export APACHE_DRILL_VERSIONS="${@:-${APACHE_DRILL_VERSIONS:-latest 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 1.10 1.11 1.12 1.13 latest}}"

APACHE_DRILL_HOST="${DOCKER_HOST:-${APACHE_DRILL_HOST:-${HOST:-localhost}}}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST##*/}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST%%:*}"
export APACHE_DRILL_HOST
export APACHE_DRILL_PORT_DEFAULT=8047
export HAPROXY_PORT_DEFAULT=8047

export DOCKER_CONTAINER="nagios-plugins-apache-drill"

check_docker_available

trap_debug_env apache_drill

test_apache_drill(){
    local version="$1"
    section2 "Setting up Apache Drill $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d
    hr
    echo "getting Apache Drill dynamic port mappings:"
    docker_compose_port "Apache Drill"
    DOCKER_SERVICE=apache-drill-haproxy docker_compose_port HAProxy
    hr
    when_ports_available "$APACHE_DRILL_HOST" "$APACHE_DRILL_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$APACHE_DRILL_HOST:$APACHE_DRILL_PORT/status" "Running"
    hr
    echo "checking HAProxy Apache Drill:"
    when_url_content "http://$APACHE_DRILL_HOST:$HAPROXY_PORT/status" "Running"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    docker_compose_version_test apache-drill "$version"
    hr
    test_drill
    echo
    hr
    echo
    section2 "Running Apache Drill HAProxy tests"
    APACHE_DRILL_PORT="$HAPROXY_PORT" \
    test_drill

    echo "Completed $run_count Apache Drill tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

test_drill(){
    expected_version="$version"
    if [ "$version" = "latest" ]; then
        expected_version=".*"
    fi
    # API endpoint not available in 0.7
    if [ "$version" != "0.7" ]; then
        run ./check_apache_drill_version.py -v -e "$expected_version"
    fi

    run_fail 2 ./check_apache_drill_version.py -v -e "fail-version"

    run_conn_refused ./check_apache_drill_version.py -v

    # ============================================================================ #

    run ./check_apache_drill_status.py -v

    run_conn_refused ./check_apache_drill_status.py -v

    # ============================================================================ #

    # API endpoint not available in 0.7
    if [ "$version" != "0.7" ]; then
        run ./check_apache_drill_status2.py -v
    fi

    run_conn_refused ./check_apache_drill_status2.py -v

    # ============================================================================ #

    # API endpoint not available in 0.7
    if [ "$version" != "0.7" ]; then
        run ./check_apache_drill_cluster_nodes.py -v -w 1

        run_fail 1 ./check_apache_drill_cluster_nodes.py -v
    fi

    run_fail 2 ./check_apache_drill_cluster_nodes.py -v -w 3 -c 2

    run_conn_refused ./check_apache_drill_cluster_nodes.py -v

    # ============================================================================ #

    # Encryption is available only in Apache Drill 1.11+
    if [ "$version" = "latest" ] || [[ "$version" > 1.10 ]]; then
        run_fail 2 ./check_apache_drill_encryption_enabled.py
    fi

    run_conn_refused ./check_apache_drill_encryption_enabled.py

    # ============================================================================ #

    # API endpoint not available in 0.7
    if [ "$version" != "0.7" ]; then
        run ./check_apache_drill_cluster_mismatched_versions.py
    fi

    run_conn_refused ./check_apache_drill_cluster_mismatched_versions.py

    # ============================================================================ #

    run $perl -T ./check_apache_drill_metrics.pl -v

    run_conn_refused $perl -T ./check_apache_drill_metrics.pl -v

    # ============================================================================ #

    run_fail 3 ./check_apache_drill_storage_plugin.py --list

    run ./check_apache_drill_storage_plugin.py --name dfs

    run ./check_apache_drill_storage_plugin.py --name dfs --type file

    run_fail 2 ./check_apache_drill_storage_plugin.py --name dfs --type wrong

    run ./check_apache_drill_storage_plugin.py -n cp --type file

    run_fail 2 ./check_apache_drill_storage_plugin.py -n hive --type hive

    run_fail 2 ./check_apache_drill_storage_plugin.py -n hbase --type hbase

    run_fail 2 ./check_apache_drill_storage_plugin.py -n mongo --type mongo

    # ============================================================================ #

    # check container query capability is working
    #
    # Apache Drill 1.10 onwards requires JDK not JRE:
    #
    # https://github.com/HariSekhon/Dockerfiles/pull/15
    #
    # looks like the Apache Drill /status API doesn't reflect the break either, raised in:
    #
    # https://issues.apache.org/jira/browse/DRILL-5990
    #
    #docker_exec sqlline -u jdbc:drill:zk=zookeeper <<< "select * from sys.options limit 1;"
    # more reliable for some versions of drill eg. 0.7
    #docker_exec sqlline -u jdbc:drill:zk=zookeeper -f /dev/stdin <<< "select * from sys.options limit 1;"
    docker_exec sqlline -u jdbc:drill:zk=zookeeper -f /dev/stdin <<< "select * from sys.drillbits;"

}

startupwait 70

run_test_versions "Apache Drill"
