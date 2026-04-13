%%% -*- mode: erlang;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%%% ex: ts=4 sw=4 ft=erlang et indentexpr=
%%%--------------------------------------------------------------------------
%%% File:    grpcbox_prometheus.erl
%%%
%%% @doc     Prometheus metrics helper for grpcbox (SERVER mode only)
%%%          This module just pushes metrics - declarations are done
%%%          in the application using grpcbox (e.g., router_prometheus.erl)
%%%
%%%          Latency buckets (in milliseconds):
%%%          - fast:   <= 100ms
%%%          - medium: 100ms < x < 200ms  
%%%          - slow:   >= 200ms
%%%
%%%          Requests taking >=90ms are logged via lager.
%%% @end
%%%-------------------------------------------------------------------------
-module(grpcbox_prometheus).

-export([
    count_rpc_started/1,
    count_rpc_handled/2,
    observe_rpc_latency/2,
    observe_rpc_latency/3,
    count_latency_bucket/1,
    inc_active_requests/0,
    dec_active_requests/0,
    get_active_requests/0,
    count_rate_limit_rejection/0
]).

-define(SERVER_STARTED, grpc_server_started_total).
-define(SERVER_HANDLED, grpc_server_handled_total).
-define(SERVER_LATENCY_MS, grpc_server_handling_milliseconds).

-define(SLOW_REQUEST_THRESHOLD_MS, 90).

%% Count RPC started
-spec count_rpc_started(binary() | string()) -> ok.
count_rpc_started(Method) ->
    catch prometheus_counter:inc(?SERVER_STARTED, [Method]),
    ok.

%% Count RPC handled with status
-spec count_rpc_handled(binary() | string(), binary() | string()) -> ok.
count_rpc_handled(Method, Status) ->
    catch prometheus_counter:inc(?SERVER_HANDLED, [Method, Status]),
    ok.

%% Observe RPC latency (in milliseconds) - without context (backward compatible)
-spec observe_rpc_latency(binary() | string(), number()) -> ok.
observe_rpc_latency(Method, LatencyMs) ->
    observe_rpc_latency(Method, LatencyMs, undefined).

%% Observe RPC latency (in milliseconds) - with context for transaction ID
-spec observe_rpc_latency(binary() | string(), number(), term()) -> ok.
observe_rpc_latency(Method, LatencyMs, Ctx) ->
    catch prometheus_histogram:observe(?SERVER_LATENCY_MS, [Method], LatencyMs),
    
    %% Track latency bucket: fast (<=40ms), medium (40-140ms), slow (>=140ms)
    count_latency_bucket(LatencyMs),
    
    %% Track slow requests (>=90ms) and log via lager
    case LatencyMs >= ?SLOW_REQUEST_THRESHOLD_MS of
        true ->
            catch prometheus_gauge:set(grpc_server_last_slow_request_milliseconds, 
                                      [Method], LatencyMs),
            catch prometheus_counter:inc(grpc_server_slow_requests_total, [Method]),
            TransId = get_transaction_id(Ctx),
            log_slow_request(Method, LatencyMs, TransId);
        false ->
            ok
    end,
    ok.

%% Count gRPC request by latency bucket
%% Input: Milliseconds
%% Buckets: fast (<=40ms), medium (40-140ms), slow (>=140ms)
-spec count_latency_bucket(number()) -> ok.
count_latency_bucket(LatencyMs) when LatencyMs =< 40 ->
    catch prometheus_counter:inc(grpc_server_latency_bucket_total, [fast]),
    ok;
count_latency_bucket(LatencyMs) when LatencyMs < 140 ->
    catch prometheus_counter:inc(grpc_server_latency_bucket_total, [medium]),
    ok;
count_latency_bucket(_LatencyMs) ->
    catch prometheus_counter:inc(grpc_server_latency_bucket_total, [slow]),
    ok.

%% Get transaction ID from context metadata
-spec get_transaction_id(term()) -> binary() | undefined.
get_transaction_id(undefined) ->
    undefined;
get_transaction_id(Ctx) ->
    try
        Metadata = grpcbox_metadata:from_incoming_ctx(Ctx),
        maps:get(<<"x-sbc-trans-id">>, Metadata, undefined)
    catch
        _:_ -> undefined
    end.

%% Log slow requests using lager (available in hermes-dyn-router)
-spec log_slow_request(binary() | string(), number(), binary() | undefined) -> ok.
log_slow_request(Method, LatencyMs, TransId) ->
    Bucket = latency_bucket(LatencyMs),
    TransIdStr = case TransId of
        undefined -> <<"unknown">>;
        _ -> TransId
    end,
    try
        lager:debug("grpc_slow_request: method=~s latency_ms=~.2f bucket=~s x_sbc_trans_id=~s",
                    [Method, LatencyMs, Bucket, TransIdStr])
    catch
        _:_ ->
            ok
    end,
    ok.

%% Determine which latency bucket a request falls into
-spec latency_bucket(number()) -> binary().
latency_bucket(LatencyMs) when LatencyMs =< 100 ->
    <<"fast_le_100ms">>;
latency_bucket(LatencyMs) when LatencyMs < 200 ->
    <<"medium_100_200ms">>;
latency_bucket(_LatencyMs) ->
    <<"slow_ge_200ms">>.

%%-------------------------------------------------------------------------
%% Active Requests Tracking (for rate limiting)
%%-------------------------------------------------------------------------

-define(ACTIVE_REQUESTS, grpc_server_active_requests).
-define(RATE_LIMIT_REJECTIONS, grpc_rate_limit_rejections_total).

%% Increment active requests counter
-spec inc_active_requests() -> ok.
inc_active_requests() ->
    catch prometheus_gauge:inc(?ACTIVE_REQUESTS),
    ok.

%% Decrement active requests counter
-spec dec_active_requests() -> ok.
dec_active_requests() ->
    catch prometheus_gauge:dec(?ACTIVE_REQUESTS),
    ok.

%% Get current active requests count
-spec get_active_requests() -> non_neg_integer().
get_active_requests() ->
    try prometheus_gauge:value(?ACTIVE_REQUESTS) of
        Val when is_number(Val) -> max(0, round(Val));
        _ -> 0
    catch
        _:_ -> 0
    end.

%% Count rate limit rejection
-spec count_rate_limit_rejection() -> ok.
count_rate_limit_rejection() ->
    catch prometheus_counter:inc(?RATE_LIMIT_REJECTIONS),
    ok.
