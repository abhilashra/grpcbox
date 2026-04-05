%%% -*- mode: erlang;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%%% ex: ts=4 sw=4 ft=erlang et indentexpr=
%%%--------------------------------------------------------------------------
%%% File:    grpcbox_prometheus_handler.erl
%%%
%%% @doc     Prometheus stats handler for grpcbox
%%%          Implements the same interface as grpcbox_oc_stats_handler
%%%          Metrics are declared in the host application (e.g., router_prometheus.erl)
%%%
%%%          Usage in sys.config:
%%%          {grpcbox, [
%%%              {servers, [
%%%                  #{grpc_opts => #{
%%%                      stats_handler => grpcbox_prometheus_handler,
%%%                      ...
%%%                  }}
%%%              ]}
%%%          ]}
%%% @end
%%%-------------------------------------------------------------------------
-module(grpcbox_prometheus_handler).

-export([handle/5]).

-record(stats, {
    start_time :: integer() | undefined
}).

%% Server RPC begin
handle(Ctx, server, rpc_begin, _, _) ->
    Method = ctx:get(Ctx, grpc_server_method, <<"">>),
    grpcbox_prometheus:count_rpc_started(server, Method),
    {Ctx, #stats{start_time = erlang:monotonic_time(microsecond)}};

%% Client RPC begin
handle(Ctx, client, rpc_begin, _, _) ->
    Method = ctx:get(Ctx, grpc_client_method, <<"">>),
    grpcbox_prometheus:count_rpc_started(client, Method),
    {Ctx, #stats{start_time = erlang:monotonic_time(microsecond)}};

%% Server RPC end
handle(Ctx, server, rpc_end, _, Stats = #stats{start_time = StartTime}) ->
    EndTime = erlang:monotonic_time(microsecond),
    Method = ctx:get(Ctx, grpc_server_method, <<"">>),
    Status = ctx:get(Ctx, grpc_server_status, <<"OK">>),
    
    LatencyMicros = EndTime - StartTime,
    
    grpcbox_prometheus:count_rpc_handled(server, Method, Status),
    grpcbox_prometheus:observe_rpc_latency(server, Method, LatencyMicros),
    
    {Ctx, Stats};

%% Client RPC end
handle(Ctx, client, rpc_end, _, Stats = #stats{start_time = StartTime}) ->
    EndTime = erlang:monotonic_time(microsecond),
    Method = ctx:get(Ctx, grpc_client_method, <<"">>),
    Status = ctx:get(Ctx, grpc_client_status, <<"OK">>),
    
    LatencyMicros = EndTime - StartTime,
    
    grpcbox_prometheus:count_rpc_handled(client, Method, Status),
    grpcbox_prometheus:observe_rpc_latency(client, Method, LatencyMicros),
    
    {Ctx, Stats};

%% Catch-all for unhandled events (in_payload, out_payload, etc.)
handle(Ctx, _, _, _, Stats) ->
    {Ctx, Stats}.
