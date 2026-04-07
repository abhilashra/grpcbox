%%% -*- mode: erlang;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%%% ex: ts=4 sw=4 ft=erlang et indentexpr=
%%%--------------------------------------------------------------------------
%%% File:    grpcbox_prometheus.erl
%%%
%%% @doc     Prometheus metrics helper for grpcbox
%%%          This module just pushes metrics - declarations are done
%%%          in the application using grpcbox (e.g., router_prometheus.erl)
%%% @end
%%%-------------------------------------------------------------------------
-module(grpcbox_prometheus).

-export([
    count_rpc_started/2,
    count_rpc_handled/3,
    observe_rpc_latency/3
]).

-define(SERVER_STARTED, grpc_server_started_total).
-define(SERVER_HANDLED, grpc_server_handled_total).
-define(SERVER_LATENCY_MICS, grpc_server_handling_microseconds).

-define(CLIENT_STARTED, grpc_client_started_total).
-define(CLIENT_HANDLED, grpc_client_handled_total).
-define(CLIENT_LATENCY_MICS, grpc_client_handling_microseconds).

%% Count RPC started
-spec count_rpc_started(server | client, binary() | string()) -> ok.
count_rpc_started(server, Method) ->
    catch prometheus_counter:inc(?SERVER_STARTED, [Method]),
    ok;
count_rpc_started(client, Method) ->
    catch prometheus_counter:inc(?CLIENT_STARTED, [Method]),
    ok.

%% Count RPC handled with status
-spec count_rpc_handled(server | client, binary() | string(), binary() | string()) -> ok.
count_rpc_handled(server, Method, Status) ->
    catch prometheus_counter:inc(?SERVER_HANDLED, [Method, Status]),
    ok;
count_rpc_handled(client, Method, Status) ->
    catch prometheus_counter:inc(?CLIENT_HANDLED, [Method, Status]),
    ok.

%% Observe RPC latency (in microseconds, like hermes-dyn-router)
-spec observe_rpc_latency(server | client, binary() | string(), number()) -> ok.
observe_rpc_latency(server, Method, LatencyMicros) ->
    catch prometheus_histogram:observe(?SERVER_LATENCY_MICS, [Method], LatencyMicros),
    
    % Track slow requests (>100ms = 100000 microseconds)
    case LatencyMicros > 100000 of
        true ->
            catch prometheus_gauge:set(grpc_server_last_slow_request_microseconds, 
                                      [Method], LatencyMicros),
            catch prometheus_counter:inc(grpc_server_slow_requests_total, [Method]);
        false ->
            ok
    end,
    ok;
observe_rpc_latency(client, Method, LatencyMicros) ->
    catch prometheus_histogram:observe(?CLIENT_LATENCY_MICS, [Method], LatencyMicros),
    
    % Track slow requests (>100ms = 100000 microseconds)
    case LatencyMicros > 100000 of
        true ->
            catch prometheus_gauge:set(grpc_client_last_slow_request_microseconds, 
                                      [Method], LatencyMicros),
            catch prometheus_counter:inc(grpc_client_slow_requests_total, [Method]);
        false ->
            ok
    end,
    ok.
