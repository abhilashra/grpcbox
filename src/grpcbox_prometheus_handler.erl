%%% -*- mode: erlang;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%%% ex: ts=4 sw=4 ft=erlang et indentexpr=
%%%--------------------------------------------------------------------------
%%% File:    grpcbox_prometheus_handler.erl
%%%
%%% @doc     Prometheus stats handler for grpcbox (SERVER mode only)
%%%          Implements the same interface as grpcbox_oc_stats_handler
%%%          Metrics are declared in the host application (e.g., router_prometheus.erl)
%%%
%%%          All latencies are recorded in MILLISECONDS.
%%%          Requests taking >100ms are logged via lager.
%%%
%%%          Latency buckets:
%%%          - fast:   <= 100ms
%%%          - medium: 100ms < x < 200ms
%%%          - slow:   >= 200ms
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

-export([handle/5, check_and_increment/0, check_and_increment/1, get_active_requests/0]).

-record(stats, {
    start_time :: integer() | undefined
}).

%% Server RPC begin
handle(Ctx, server, rpc_begin, _, _) ->
    Method = ctx:get(Ctx, grpc_server_method, <<"">>),
    grpcbox_prometheus:count_rpc_started(Method),
    {Ctx, #stats{start_time = erlang:monotonic_time(millisecond)}};

%% Server RPC end
handle(Ctx, server, rpc_end, _, Stats = #stats{start_time = StartTime}) ->
    EndTime = erlang:monotonic_time(millisecond),
    Method = ctx:get(Ctx, grpc_server_method, <<"">>),
    Status = ctx:get(Ctx, grpc_server_status, <<"OK">>),
    
    LatencyMs = EndTime - StartTime,
    
    grpcbox_prometheus:count_rpc_handled(Method, Status),
    grpcbox_prometheus:observe_rpc_latency(Method, LatencyMs, Ctx),
    
    {Ctx, Stats};

%% Catch-all for unhandled events (client events, in_payload, out_payload, etc.)
handle(Ctx, _, _, _, Stats) ->
    {Ctx, Stats}.

%%-------------------------------------------------------------------------
%% Rate Limiting API
%%-------------------------------------------------------------------------

%% Get current active requests count
-spec get_active_requests() -> non_neg_integer().
get_active_requests() ->
    grpcbox_prometheus:get_active_requests().

%% Check limit and increment if under limit (uses default high_load from lookup_engine app)
-spec check_and_increment() -> ok | {reject, non_neg_integer(), non_neg_integer()}.
check_and_increment() ->
    HighLoad = application:get_env(lookup_engine, high_load, 150),
    check_and_increment(HighLoad).

%% Check limit and increment if under limit (with explicit limit)
-spec check_and_increment(non_neg_integer()) -> ok | {reject, non_neg_integer(), non_neg_integer()}.
check_and_increment(HighLoad) ->
    ActiveCount = grpcbox_prometheus:get_active_requests(),
    if
        ActiveCount >= HighLoad ->
            {reject, ActiveCount, HighLoad};
        true ->
            grpcbox_prometheus:inc_active_requests(),
            ok
    end.
